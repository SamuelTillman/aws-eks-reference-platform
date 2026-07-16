# CLAUDE.md

Operating guide for working in this repo. Read this before touching Terraform or
committing. It captures the conventions that aren't obvious from a file scan; for
*why*, see the ADRs in [docs/adr/](docs/adr/).

## What this is

A public, forkable AWS multi-account reference platform (org → landing zone →
EKS → GPU/AI), built in layers. See [README.md](README.md) for the layer map and
[docs/adr/](docs/adr/) for decisions. Nothing here stores long-lived credentials.

## Hard rules (do not break)

- **Zero stored credentials.** Humans use IAM Identity Center SSO; CI uses GitHub
  OIDC; workloads use IAM roles. Never create IAM users or access keys, and never
  introduce a credential that outlives a session.
- **Never commit:** `*.tfvars`, `backend.hcl`, state files, or **account IDs**
  (use `<MGMT_ACCOUNT_ID>`-style placeholders in tracked files). These are
  gitignored, keep it that way. **Scan `git diff --cached` for 12-digit IDs and
  the real account IDs before every commit.**
- **Never apply an unshown plan.** Always `plan` → show the human the plan →
  wait for explicit approval → `apply`. Especially at the org level. Save plans
  with `-out=<stack>.tfplan` and apply that exact file.
- **Never touch** the management-account root, IAM Identity Center *enablement*,
  or billing settings by automation, those are documented manual bootstrap
  steps ([docs/bootstrap.md](docs/bootstrap.md)).
- **Decisions get an ADR** in `docs/adr/`, numbered sequentially. Update the
  index table in [docs/adr/README.md](docs/adr/README.md).

## AWS access

- Local runs authenticate via SSO: prefix Terraform with `AWS_PROFILE=refplatform-mgmt`
  (management account, `AdministratorAccess` via SSO).
- CI authenticates via the `refplatform-github-actions` OIDC role (repo variable
  `AWS_ROLE_ARN`). The plan workflow is `.github/workflows/terraform-plan.yml`
  (plan-only).

## Terraform workflow (every stack)

```bash
cd terraform/<stack>
cp backend.hcl.example backend.hcl          # set bucket = the state bucket (gitignored)
cp terraform.tfvars.example terraform.tfvars # fill values (gitignored)
AWS_PROFILE=refplatform-mgmt terraform init -backend-config=backend.hcl
AWS_PROFILE=refplatform-mgmt terraform plan -out=<stack>.tfplan   # SHOW + APPROVE before apply
AWS_PROFILE=refplatform-mgmt terraform apply <stack>.tfplan
```

- **Backend:** partial S3 config. `versions.tf` holds only non-sensitive settings;
  the account-specific `bucket` lives in gitignored `backend.hcl` (see
  [ADR-0003](docs/adr/0003-layer-0-deployment-decisions.md)). S3 native locking
  (`use_lockfile`), no DynamoDB. Terraform >= 1.10, AWS provider ~> 5.0.
- **Lockfiles are committed** (`.terraform.lock.hcl`) with multi-platform hashes.
  After changing providers: `terraform providers lock -platform=linux_amd64
  -platform=darwin_amd64 -platform=darwin_arm64`.
- Run `terraform fmt -recursive` before committing.

## Stack layout & state keys

Flat under `terraform/`, one state key per stack (all in the one S3 bucket):

| Stack | Key | Scope |
|---|---|---|
| `bootstrap` | `bootstrap/terraform.tfstate` | state bucket + GitHub OIDC (mgmt) *(Layer 0, done)* |
| `org` | `org/terraform.tfstate` | OUs, member accounts, SCPs (mgmt) *(Layer 0, done)* |
| `identity` | `identity/terraform.tfstate` | Identity Center permission sets/groups/assignments (mgmt) *(Layer 1, done)* |
| `logging` | `logging/terraform.tfstate` | org CloudTrail + central log archive (mgmt + security) *(Layer 1, done)* |
| `config` | `config/terraform.tfstate` | org-wide AWS Config recorders + aggregator (delegated to security) *(Layer 1, done)* |
| `security` | `security/terraform.tfstate` | GuardDuty/Security Hub/Access Analyzer (delegated to security) *(Layer 1, done)* |
| `cicd` | `cicd/terraform.tfstate` | per-account OIDC deploy roles + central ECR *(Layer 1, done)* |
| `networking` | `networking/terraform.tfstate` | TGW centralized-egress hub, VPCs, flow logs (cross-account) *(Layer 1, done)* |

## Cross-account model (Layer 1+)

Stacks acting inside member accounts enter as management, then assume each
account's `OrganizationAccountAccessRole` via a provider alias. **Account IDs are
never hardcoded**, read them from the `org` stack's remote state:

```hcl
data "terraform_remote_state" "org" {
  backend = "s3"
  config  = { bucket = var.state_bucket, key = "org/terraform.tfstate", region = var.aws_region }
}
```

Org-wide security services use **delegated administration to the `security`
account** (see [ADR-0004](docs/adr/0004-layer-1-landing-zone-architecture.md)).

## Commits

- Author identity is the user's GitHub `noreply` email (set in repo-local git
  config) so commits attribute correctly on a public repo without exposing a real
  address.
- End commit messages with a `Co-Authored-By: Claude ...` trailer.
- Only commit/push when asked. Scan for secrets/IDs first (see Hard rules).

## Cost discipline

Paid org services (GuardDuty, Security Hub, and especially **AWS Config**, the
largest variable cost) sit behind `enable_*` flags so the platform can be stood
down to near-zero and rebuilt from code. Keep everything destroyable.
