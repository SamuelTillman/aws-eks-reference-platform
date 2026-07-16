# ADR-0003: Layer 0 deployment decisions

**Status:** Accepted · **Date:** 2026-07

## Context

Layer 0 (org bootstrap: state backend, GitHub OIDC, OUs, member accounts,
SCPs) was deployed interactively from a local workstation using IAM Identity
Center (SSO) credentials. Several decisions came up during the deployment that
weren't fully settled by the code as written. This ADR records them so the
reasoning is legible to anyone forking or auditing the repo.

## Decisions

### 1. Home region: `us-east-1`; allowed regions: `us-east-1` + `us-east-2`

The platform home region (the `aws_region` in both stacks, and the region where
IAM Identity Center is enabled) is **`us-east-1`**. The `region-allowlist` SCP
permits **`us-east-1` and `us-east-2`**.

- `us-east-1` keeps the tfvars defaults untouched and is where global-ish
  services (IAM, CloudFront, Route 53, billing) are anchored anyway.
- Identity Center's home region is effectively permanent (moving it means
  deleting and recreating the instance), so it was chosen deliberately, not by
  default.
- `us-east-2` is included as an adjacent DR/failover region so workloads have
  somewhere to go without editing the guardrail SCP later.

Revisit if data-residency requirements ever demand a non-US home region.

### 2. Terraform state backend: partial S3 configuration

The handoff called for uncommenting the S3 `backend` block and filling in the
real bucket name. The bucket name embeds the **management account ID**, and
`versions.tf` is committed to a **public** repo, which conflicts with the hard
rule "never commit account IDs (use placeholders)."

Resolution: **partial backend configuration.** `versions.tf` holds only the
non-sensitive settings (`key`, `region`, `use_lockfile`, `encrypt`); the
account-specific `bucket` lives in a **gitignored `backend.hcl`**, supplied at
init time via `terraform init -backend-config=backend.hcl`. A committed
`backend.hcl.example` with a `<MGMT_ACCOUNT_ID>` placeholder mirrors the
existing `tfvars` / `.tfvars.example` convention, so the pattern is consistent
and forkable.

State locking uses **S3 native locking** (`use_lockfile`, Terraform >= 1.10),
no DynamoDB table required.

### 3. Org stack initialized directly against S3 (no local-then-migrate)

The `bootstrap` stack must run on local state first because it *creates* the
state bucket, then migrates (`init -migrate-state`). The `org` stack has no such
dependency, the bucket already exists, so it was initialized **directly
against the S3 backend** from its first `init`. This keeps org state (which
contains member account IDs) off local disk entirely.

### 4. Layer 0 applies run locally via SSO; CI is plan-only

All Layer 0 `apply` operations were run **locally with human SSO credentials**
behind an explicit approval gate. The GitHub Actions workflow
(`terraform-plan.yml`) runs **`plan` only**, on pull requests, via the OIDC
role, it never applies. Automated apply-via-CI (with environment protection
rules and a reviewed pipeline) is deferred to Layer 1 as a deliberate design
choice, not an oversight. The OIDC role and `AWS_ROLE_ARN` repo variable are in
place so CI can take over when that decision is made.

### 5. Account-creation quota: no workaround needed

New organizations often ship with a low default quota on concurrent account
creation (~4-5). Creating all four member accounts at once succeeded with no
`CONSTRAINT_VIOLATION` / limit error; one account (`workloads-dev`) simply took
~80s to vend asynchronously. No Service Quotas increase or Support ticket was
required. If a fork hits the limit, request an increase for **"Accounts" under
the AWS Organizations service** in Service Quotas (or via a Support case) and
re-apply, Terraform will create only the accounts that don't yet exist.

### 6. Reconciled a console-created SCP into code

Enabling the organization via the console left an unmanaged SCP,
`DenyLeaveAndCloseAccount`, attached to **Root**, denying
`organizations:LeaveOrganization` and `account:CloseAccount`. It was invisible
to Terraform and to anyone reading the repo, violating "everything is code."

Resolution: the managed `deny-leave-org` policy was extended to also deny
`account:CloseAccount` (and renamed **`deny-leave-and-close`**), making it a
superset of the console policy. The unmanaged console SCP was then detached from
Root and deleted. The org now has exactly three managed SCPs
(`region-allowlist`, `deny-root-user`, `deny-leave-and-close`) plus the default
`FullAWSAccess`, each attached to all three top-level OUs, all in git.

## Consequences

- Initializing either stack requires `-backend-config=backend.hcl`; this is
  documented in `docs/bootstrap.md`. CI must supply the bucket the same way.
- The GitHub OIDC role is currently `AdministratorAccess` with repo trust scoped
  to `:*` (any branch/PR). This is the widest it will ever be; narrowing to
  specific branches/environments and least-privilege policies is tracked for a
  future layer.
- SCP guardrails apply to member accounts only (SCPs never restrict the
  management account). The region allowlist will deny any regional API call
  outside `us-east-1`/`us-east-2`, expected, and the reason new regions require
  a conscious SCP change.
