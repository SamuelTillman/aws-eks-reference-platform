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

## 2. plan CI: OIDC assume-role "Not authorized" (fixed)

- **Where:** `plan` job, `Configure AWS credentials (OIDC)` step.
- **Symptom:** `Could not assume role with OIDC: Not authorized to perform
  sts:AssumeRoleWithWebIdentity`. `discover` and `validate` pass; only the cloud
  `plan` fails. This was the first time the plan workflow actually attempted the
  cross-account assume (the prior workflow was stale and never ran green).
- **Root cause:** this account emits **immutable-ID OIDC subjects**. A debug step
  printing the token claims showed the real `sub` was
  `repo:SamuelTillman@141371265/aws-eks-reference-platform@1302268994:pull_request`,
  with numeric owner/repo IDs appended. The trust policy matched the plain
  `repo:OWNER/REPO:*`, which the `@<id>` form never matches, so STS rejected it.
- **False lead:** switching the condition to the (always-plain) `repository`
  claim was rejected by AWS: `MalformedPolicyDocument ... must evaluate ...
  token.actions.githubusercontent.com:sub or ...:job_workflow_ref`. AWS *requires*
  the GitHub-OIDC trust to condition on `sub` (or `job_workflow_ref`).
- **Fix:** match `sub` against the immutable form, built from two new bootstrap
  variables `github_owner_id`/`github_repo_id` (public numeric IDs, not account
  IDs); empty falls back to the plain `repo:OWNER/REPO:*`. Get the IDs with
  `gh api repos/OWNER/REPO --jq '{owner: .owner.id, repo: .id}'`.
- **Prevention:** forkers whose accounts emit immutable subjects set those two
  vars; the plain form remains the default.
- **Status:** fixed (bootstrap re-applied; trust now matches the immutable sub).

## 3. plan CI: bootstrap stack fails on missing required variable (fixed)

- **Where:** `plan` job, `bootstrap` stack (surfaced when the OIDC fix touched
  `terraform/bootstrap`, so `discover` added it to the matrix).
- **Symptom:** `Error: No value for required variable` for `github_org`.
- **Root cause:** `terraform.tfvars` is gitignored, so CI has no value for
  bootstrap's required `github_org` (and the immutable-ID vars).
- **Fix:** the `plan` job exports the GitHub identity from the Actions context
  as `TF_VAR_github_org` / `github_repo` / `github_owner_id` / `github_repo_id`
  (`github.repository_owner`, `github.event.repository.name`,
  `github.repository_owner_id`, `github.repository_id`). Forkable and always
  matches the running repo; undeclared `TF_VAR_*` are ignored by other stacks.
- **Status:** fixed.

## 4. kubectl access: the --role-arn kubeconfig exec hangs

- **Where:** connecting to the `refplatform-dev` cluster from a workstation.
- **Symptom:** `aws eks update-kubeconfig --role-arn <OrganizationAccountAccessRole>`
  writes a working kubeconfig, but every `kubectl` call then hangs (the per-call
  `aws eks get-token --role-arn ...` exec did not return). The cluster itself was
  healthy: its endpoint resolved to public IPs and `/livez` returned 200 in
  &lt;0.5s, and the admin IP was on the endpoint allowlist.
- **Fix that works:** assume the account role once, export the temporary
  credentials, and run `update-kubeconfig` WITHOUT `--role-arn` so the exec uses
  the ambient creds:
  ```sh
  creds=$(aws sts assume-role --role-arn arn:aws:iam::<workloads-dev>:role/OrganizationAccountAccessRole \
            --role-session-name kubectl --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  export AWS_ACCESS_KEY_ID=$(echo "$creds"|cut -f1) AWS_SECRET_ACCESS_KEY=$(echo "$creds"|cut -f2) AWS_SESSION_TOKEN=$(echo "$creds"|cut -f3)
  aws eks update-kubeconfig --name refplatform-dev --region us-east-1
  kubectl get nodes
  ```
- **Note:** the cluster creator (the assumed OrganizationAccountAccessRole) is the
  bootstrap cluster-admin; the SSO Administrator role is also a cluster-admin
  access entry. An expired SSO token presents the same hang, so check
  `aws sts get-caller-identity` first.
