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

## 7. single-NAT flag had no effect on a CI rebuild (uncommitted wiring)

- **Stack:** `terraform/networking`
- **Symptom:** a button rebuild came up with 3 NAT gateways (per-AZ), not the
  intended 1, even with `egress_single_nat=true` passed. `terraform plan`
  reported "No changes" in CI, but the identical plan locally wanted to destroy 2.
- **Root cause:** the line wiring the egress module to the flag,
  `single_nat_gateway = var.egress_single_nat` in `vpcs.tf`, was added in the
  single-NAT change but never `git add`ed, so it lived only in the local working
  tree. Local applies honored it (single NAT); CI, which checks out `main`, did
  not (the module never received the flag, so it defaulted to per-AZ).
- **How it was found:** state was identical in both (same serial + NAT count),
  the CLI version was pinned the same, and `-var` was confirmed passed, so the
  only remaining difference was the config. `git show HEAD:.../vpcs.tf` showed
  the wiring was uncommitted (chased TF_VAR/`-var`/version dead ends first).
- **Fix:** commit the wiring line.
- **Prevention:** CI (`main`), not the local working tree, is the source of
  truth. When a change works locally but not in CI, diff `git show HEAD:<file>`
  against local before blaming Terraform, variables, or versions.

## 8. NAT deletion: EIP release races the ENI teardown

- **Stack:** `terraform/networking`
- **Symptom:** reducing the NAT tier (3 to 1) destroyed the NAT gateways but then
  failed releasing their EIPs: `ReleaseAddress ... InvalidNetworkInterfaceID.NotFound:
  The networkInterface ID 'eni-...' does not exist`.
- **Root cause:** deleting a NAT gateway removes its ENI; releasing the EIP right
  after races that teardown (the EIP still references the now-gone ENI). Eventual
  consistency.
- **Fix:** re-run the apply. The NATs are already gone, so the second pass
  releases the orphaned EIPs cleanly.

## 9. Org conformance pack create exceeds Terraform's default 10m timeout

- **Stack:** `terraform/config`
- **Symptom:** `aws_config_organization_conformance_pack` apply failed with
  `timeout while waiting for state to become 'CREATE_SUCCESSFUL' (last state:
  'CREATE_IN_PROGRESS', timeout: 10m0s)`. The pack was in fact created and still
  deploying (it rolls rules out to every member account sequentially); Terraform
  just gave up waiting and left the resource **tainted**, which would force a
  wasteful destroy+recreate on the next apply.
- **Root cause:** org conformance packs routinely take 15-20 min to reach
  `CREATE_SUCCESSFUL`; the AWS provider's default create timeout is 10 min.
- **Fix:** add a `timeouts { create/update/delete = "30m" }` block to the
  resource. For the already-running pack, `terraform untaint
  aws_config_organization_conformance_pack.baseline[0]` so the in-progress pack is
  kept (a re-plan then shows no changes); it finishes on its own.
- **Prevention:** any org-wide Config/conformance resource gets a generous
  `timeouts` block up front. Check real status with
  `aws configservice describe-organization-conformance-pack-statuses --region
  us-east-1` from the delegated-admin (security) account, and remember to pass
  `--region us-east-1`: a region-less call hits us-west-1 and the region-allowlist
  SCP denies it (a red herring that looks like a permissions problem).

## Operational notes

- **SSO session expiry vs. background jobs.** A background retry loop for the
  aggregator failed with `InvalidGrantException` once the local SSO token
  expired during a pause. Long-running background jobs outlive the SSO token,
  re-authenticate with `aws sso login --profile refplatform-mgmt` and re-run.
- **Partial applies are normal here.** Several stacks applied most resources and
  failed on one org-service quirk; re-applying after the fix created only the
  remaining resource (state already held the rest).
- **Stale state lock from a cancelled run.** A `terraform` step cancelled
  mid-operation can leave the S3 native lock (`use_lockfile`) behind as a
  `<key>.tflock` object, so the next run fails with "Error acquiring the state
  lock". Clear it with
  `aws s3 rm s3://<state-bucket>/<stack>/terraform.tfstate.tflock` (or
  `terraform force-unlock <id>`).
- **Pin the Terraform CLI in CI.** `hashicorp/setup-terraform` defaults to
  `latest`; pin `terraform_version` so runs are reproducible and match the
  version the config is developed and tested against.
