# Layer 1 deployment issues & fixes

A running log of every non-trivial issue hit while deploying the Layer 1
landing-zone foundation, with root cause and fix. The point: a forker (or future
me) shouldn't have to rediscover any of these. See also
[docs/layer1-plan.md](layer1-plan.md) and
[ADR-0004](adr/0004-layer-1-landing-zone-architecture.md).

## Cross-cutting theme: org-service enablement is imperative

Terraform does **not** enable AWS Organizations *trusted service access* or
*delegated administration* the way the console does. Every org-wide service
needs its trusted access (and, where used, delegated admin) enabled explicitly,
and several have per-service quirks below. General fix:

```bash
aws organizations enable-aws-service-access --service-principal <svc>.amazonaws.com
```

Services enabled for this platform: `sso`, `cloudtrail`, `guardduty`,
`securityhub`, `access-analyzer`, `config`, `config-multiaccountsetup`.

---

## 1. CloudTrail org trail: trusted access not auto-enabled

- **Stack:** `terraform/logging`
- **Symptom:** `aws_cloudtrail` apply → `CloudTrailAccessNotEnabledException: your
  organization hasn't enabled CloudTrail service access`.
- **Root cause:** Terraform's `CreateTrail` (unlike the console) does not
  auto-enable CloudTrail trusted access in Organizations.
- **Fix:** `enable-aws-service-access --service-principal cloudtrail.amazonaws.com`,
  then re-apply. The other 7 resources had already created; only the trail
  retried.
- **Prevention:** pre-enable trusted access for every org service before apply.

## 2. IAM Access Analyzer: SLR missing in management account

- **Stack:** `terraform/security`
- **Symptom:** `CreateAnalyzer` (ORGANIZATION) → `ConflictException: Access
  Analyzer Service Linked Role is not in the organizational management account`.
- **Root cause:** an org analyzer created by the delegated admin requires the
  `AWSServiceRoleForAccessAnalyzer` SLR to exist in the **management** account;
  trusted-access enablement created it only in the delegated-admin (security)
  account.
- **Fix:** manage the management-account SLR explicitly
  (`aws_iam_service_linked_role.access_analyzer`, default/management provider).
- **Secondary (IAM eventual consistency):** the freshly created SLR wasn't
  immediately visible, so the analyzer still failed. Added a `time_sleep` (30s)
  between the SLR and the analyzer.

## 3. Security Hub: stray legacy CIS 1.2.0 standard

- **Stack:** `terraform/security`
- **Symptom:** verification showed three standards; **CIS 1.2.0** was enabled but
  unmanaged (we only declared FSBP + CIS 1.4).
- **Root cause:** `aws_securityhub_account` defaults `enable_default_standards =
  true`, which auto-subscribed the legacy defaults (CIS 1.2.0) at enable time.
- **Fix:** set `enable_default_standards = false` so fresh builds skip it; because
  that argument is create-only/**ForceNew** (changing it would destructively
  replace the account), guarded it with `lifecycle { ignore_changes = [...] }`.
  Disabled the already-subscribed CIS 1.2.0 out-of-band with
  `securityhub batch-disable-standards`.

## 4. AWS Config org aggregator: dual delegated-admin registration required

- **Stack:** `terraform/config`
- **Symptom:** `PutConfigurationAggregator` → `OrganizationAccessDeniedException:
  This action can only be performed if you are a registered delegated
  administrator for AWS Config...`. Persisted well beyond any propagation window.
- **Misdiagnosis:** first attributed to slow delegated-admin propagation (AWS
  Config genuinely can lag Organizations by minutes). Ruled out after the error
  persisted >30 min and direct CLI reproduction.
- **Root cause:** the aggregator's delegated-admin check requires the account
  registered under **`config.amazonaws.com`**, not only
  **`config-multiaccountsetup.amazonaws.com`**. Only the latter had been
  registered.
- **Fix:** also register `config.amazonaws.com`
  (`aws_organizations_delegated_administrator.config_service`); the aggregator
  then created immediately. The out-of-band registration was `terraform import`ed
  so code and state match.

## 5. Config stack replaces 5 IAM attachments on every apply

- **Stack:** `terraform/config`
- **Symptom:** an unrelated apply (adding a TLS-only bucket policy) planned
  `5 to add, 5 to destroy`, replacing `module.config_*.aws_iam_role_policy_attachment.config`
  in all five accounts.
- **Root cause:** the module builds the `AWS_ConfigRole` policy ARN from
  `data.aws_partition.current`, which resolves to "known after apply", so the
  attachment's `policy_arn` reads as computed and Terraform force-replaces it.
  Detaching/reattaching the identical managed policy does not stop recording
  (verified: all five recorders stayed `recording=True`, `lastStatus=SUCCESS`).
- **Fix (optional):** hardcode `arn:aws:iam::aws:policy/service-role/AWS_ConfigRole`
  (partition `aws`) in the module, or otherwise stabilize the partition lookup,
  to stop the churn. Harmless but noisy.
- **Prevention:** read destroy/replace plans in full before applying, even for a
  one-line change; a "known after apply" on a data source can force replacements.

## 6. TGW rebuild: cross-account attachment races RAM propagation

- **Stack:** `terraform/networking`
- **Symptom:** on a rebuild, `aws_ec2_transit_gateway_vpc_attachment.dev/.prod`
  fail with `InvalidTransitGatewayID.NotFound: Transit Gateway tgw-... was deleted
  or does not exist`, even though the TGW was just created. Passed on the first
  deploy, raced on a faster rebuild.
- **Root cause:** the TGW lives in `shared-services` and is shared to the workload
  accounts via RAM. The attachments run in the workload accounts and already
  `depends_on` the `aws_ram_principal_association`, but RAM sharing is eventually
  consistent: the association returns before the shared TGW is visible in the
  target account, so an attachment created immediately after cannot find it.
- **Fix:** a `time_sleep.ram_propagation` (45s) between the RAM associations and
  the cross-account attachments (needs the `hashicorp/time` provider). Ordering
  via `depends_on` was not enough; propagation needs a brief wait.
- **Immediate unblock:** just re-run the apply, the TGW and share already exist
  and have propagated by the second run.

## Operational notes

- **SSO session expiry vs. background jobs.** A background retry loop for the
  aggregator failed with `InvalidGrantException` once the local SSO token
  expired during a pause. Long-running background jobs outlive the SSO token,
  re-authenticate with `aws sso login --profile refplatform-mgmt` and re-run.
- **Partial applies are normal here.** Several stacks applied most resources and
  failed on one org-service quirk; re-applying after the fix created only the
  remaining resource (state already held the rest).
