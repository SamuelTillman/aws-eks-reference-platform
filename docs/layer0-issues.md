# Layer 0 deployment issues & fixes

Running log of non-trivial issues hit while deploying Layer 0 (org bootstrap).
Layer 0 was smoother than Layer 1, mostly reconciliations and decisions rather
than hard API failures. The reasoning behind each is in
[ADR-0003](adr/0003-layer-0-deployment-decisions.md); this is the quick-reference
issue log (companion to [docs/layer1-issues.md](layer1-issues.md)).

## 1. Unmanaged console-created SCP on Root

- **Stack:** `terraform/org`
- **Symptom:** post-apply verification found a 4th SCP,
  `DenyLeaveAndCloseAccount`, attached to the org **Root** but absent from
  Terraform, an invisible guardrail (violates "everything is code").
- **Root cause:** the AWS console's "create organization / enable all features"
  flow auto-creates and attaches this recommended SCP.
- **Fix:** folded its intent into our managed policy, extended `deny-leave-org`
  to also deny `account:CloseAccount` and renamed it `deny-leave-and-close`
  (a superset of the console one), then detached and deleted the console SCP.
  The org now has exactly the three managed SCPs plus `FullAWSAccess`.

## 2. Account ID would leak into a public repo via the backend block

- **Stack:** `terraform/bootstrap` (and every stack after)
- **Symptom:** the handoff said to hardcode the state bucket name in
  `versions.tf`, but the bucket name embeds the **management account ID** and
  `versions.tf` is committed to a **public** repo, conflicting with the hard
  "never commit account IDs" rule.
- **Root cause:** Terraform backend blocks can't interpolate variables.
- **Fix:** **partial backend configuration**, non-sensitive settings in
  `versions.tf`, the account-specific `bucket` in a gitignored `backend.hcl`
  supplied via `terraform init -backend-config=backend.hcl`, with a committed
  `backend.hcl.example` placeholder. Now the standard pattern for every stack.

## 3. Account-creation quota (anticipated, did not occur)

- **Stack:** `terraform/org`
- **Concern:** new organizations often ship with a low quota (~4-5) on concurrent
  account creation; the plan creates 4 at once.
- **Outcome:** **no error**, all four accounts vended (one took ~80s async). No
  Service Quotas increase or Support case needed.
- **If a fork hits it:** request an increase for "Accounts" under AWS
  Organizations in Service Quotas, then re-apply (Terraform creates only the
  missing accounts).

## 4. Provider lockfiles were gitignored

- **Symptom:** the initial `.gitignore` ignored `.terraform.lock.hcl`, so
  provider versions/checksums weren't pinned in VCS, the opposite of Terraform's
  recommendation and a reproducibility gap for CI.
- **Fix:** un-ignored the lockfiles and committed them with multi-platform
  checksums: `terraform providers lock -platform=linux_amd64
  -platform=darwin_amd64 -platform=darwin_arm64` (Linux for CI, both Mac arches
  for dev/forkers).

## Note

Unlike Layer 1, Layer 0 hit **no** org-service trusted-access / delegated-admin
failures, because Layer 0 only operates in the management account and doesn't
enable org-wide services. That whole class of issue starts in Layer 1
(see [docs/layer1-issues.md](layer1-issues.md)).
