# Layer 2 deployment issues & fixes

A running log of every non-trivial issue hit while building the Layer 2 EKS
platform, with root cause and fix. The point: a forker (or future me) shouldn't
have to rediscover any of these. See also
[ADR-0007](adr/0007-eks-cluster-foundation.md) and the plan workflow
[.github/workflows/terraform-plan.yml](../.github/workflows/terraform-plan.yml).

---

## 1. plan CI: mgmt account ID leaked into the public run log (fixed)

- **Where:** `.github/workflows/terraform-plan.yml`, `plan` job.
- **Symptom:** the `Configure AWS credentials` step printed
  `role-to-assume: arn:aws:iam::<MGMT_ACCOUNT_ID>:role/refplatform-github-actions`
  in clear text on a world-readable log.
- **Root cause:** `AWS_ROLE_ARN` was a repo **variable**. GitHub echoes an
  action's `with:` inputs in the log, and variables (unlike secrets) are not
  masked, so the ARN (which embeds the account ID) printed verbatim.
- **Fix:** moved the value to a repo **secret** `AWS_ROLE_ARN` (masked as `***`
  in the input echo), deleted the variable, and deleted the leaked run. Same
  treatment as `TF_STATE_BUCKET`.
- **Prevention:** any value embedding an account ID that is passed to an action
  input must be a secret, not a variable.

## 2. plan CI: OIDC assume-role "Not authorized" (investigating)

- **Where:** `plan` job, `Configure AWS credentials (OIDC)` step.
- **Symptom:** `Could not assume role with OIDC: Not authorized to perform
  sts:AssumeRoleWithWebIdentity`. `discover` and `validate` pass; only the cloud
  `plan` fails. This is the first time the plan workflow has actually attempted
  the cross-account assume (the prior workflow was stale and never ran green).
- **Checked so far (all correct):** the deployed `refplatform-github-actions`
  trust policy matches the repo (`aud = sts.amazonaws.com`, `sub` StringLike
  `repo:SamuelTillman/aws-eks-reference-platform:*`); the GitHub OIDC provider
  exists with audience `sts.amazonaws.com` and the standard thumbprint; the
  `AWS_ROLE_ARN` secret points at that role in the mgmt account.
- **Next step:** a temporary debug step in the `plan` job prints the token's
  real `sub`/`aud` claims to confirm what STS actually receives, since a correct
  trust policy plus a rejected assume implies the live claim differs from the
  expected `repo:OWNER/REPO:...` form.
- **Status:** open.
