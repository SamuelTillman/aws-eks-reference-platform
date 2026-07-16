# ADR-0004: Layer 1 landing zone architecture

**Status:** Accepted · **Date:** 2026-07

## Context

Layer 0 created the organization: OUs, four member accounts, guardrail SCPs, a
Terraform state backend, and GitHub OIDC, all managed from the **management
account only**. Layer 1 builds the *landing zone*: the shared identity, audit,
and security backbone that every later layer (and the EKS platform in Layer 2)
depends on.

Unlike Layer 0, Layer 1 provisions resources **inside member accounts** and
relies on **organization-wide services with delegated administration**. That
introduces two cross-cutting concerns, a cross-account execution model and a
delegated-admin model, that must be decided once and applied consistently.

The Layer 1 scope named in the project roadmap is broad: identity, centralized
logging, centralized security, CI/CD, a data pipeline, and a Bedrock RAG
service. Treating all six as one unit would produce an unreviewable change with
a huge blast radius. This ADR scopes Layer 1 and fixes its foundational
patterns; heavier workstreams get their own ADRs.

## Decisions

### 1. Scope Layer 1 to the security foundation; defer the rest

**Built now (this ADR + `docs/layer1-plan.md`):**
- **Identity**, Identity Center permission sets, groups, and account assignments
- **Centralized logging**, org-wide CloudTrail + AWS Config aggregation into the
  `security` account as the log archive
- **Centralized security**, GuardDuty, Security Hub, and IAM Access Analyzer,
  organization-enabled via delegated administration to `security`

**Deferred to their own ADRs/efforts (still Layer 1, built later):**
- **Shared-services networking + CI/CD**, VPC hub, ECR, cross-account deploy
  roles (ADR-0005, planned)
- **Data pipeline** (ADR-0006, planned)
- **Bedrock RAG service**, effectively a full application; knowledge base +
  vector store + retrieval API (ADR-0007, planned)

Rationale: the identity/logging/security triad is the true "landing zone", it
is low-risk, high-leverage, and a prerequisite for everything above it. The RAG
service is an application, not landing-zone plumbing, and shouldn't gate the
foundation.

### 2. Cross-account execution model: assume-role via provider aliases

Terraform continues to enter as the **management** identity (local SSO profile
`refplatform-mgmt`; CI uses the management OIDC role). To act inside a member
account, a provider alias **assumes that account's
`OrganizationAccountAccessRole`** (created by Layer 0's account vending):

```hcl
provider "aws" {
  alias  = "security"
  region = var.aws_region
  assume_role { role_arn = "arn:aws:iam::${local.account_ids.security}:role/OrganizationAccountAccessRole" }
}
```

**Account IDs are never hardcoded.** Each Layer 1 stack reads them from the
`org` stack's remote state:

```hcl
data "terraform_remote_state" "org" {
  backend = "s3"
  config  = { bucket = var.state_bucket, key = "org/terraform.tfstate", region = var.aws_region }
}
locals { account_ids = data.terraform_remote_state.org.outputs.account_ids }
```

`var.state_bucket` (which embeds the management account ID) is supplied via the
gitignored tfvars, consistent with the Layer 0 no-account-IDs-in-git rule.

### 3. Delegated administration to the `security` account

The organization's security services are administered from the `security`
account, not the management account (AWS best practice: keep the management
account minimal). For each service, the management provider **registers
`security` as the delegated administrator**; the service's org-wide
configuration is then managed through the `security` provider alias:

| Service | Delegated-admin registration | Org config runs in |
|---|---|---|
| GuardDuty | `aws_guardduty_organization_admin_account` | `security` |
| Security Hub | `aws_securityhub_organization_admin_account` | `security` |
| IAM Access Analyzer | `aws_organizations_delegated_administrator` | `security` |
| AWS Config aggregator | `aws_organizations_delegated_administrator` | `security` |

Org CloudTrail is created as an **organization trail in the management account**
(where org trails must originate) writing to a central bucket the `security`
account owns.

### 4. Stack / state layout: one stack per concern

Extending the flat Layer 0 layout (`terraform/{bootstrap,org}`):

| Stack | State key | Purpose | Providers |
|---|---|---|---|
| `terraform/identity` | `identity/terraform.tfstate` | permission sets, groups, assignments | management |
| `terraform/logging` | `logging/terraform.tfstate` | org CloudTrail + central log bucket + Config aggregator | management + `security` + per-account aliases |
| `terraform/security` | `security/terraform.tfstate` | GuardDuty, Security Hub, Access Analyzer | management + `security` |

Each stack uses the **same partial S3 backend** pattern as Layer 0
(`-backend-config=backend.hcl`, gitignored bucket). Separate state per concern
keeps blast radius small and lets logging/security be destroyed/rebuilt
independently.

### 5. Central logging lands in the `security` account

The `security` account doubles as the **log archive**. It owns:
- A KMS-encrypted, versioned, public-access-blocked S3 bucket receiving the org
  CloudTrail (management + all member accounts).
- The AWS Config **organization aggregator**, giving a single-pane view of
  resource configuration across all accounts.

This keeps audit data in a low-privilege account separate from where workloads
run, so a workload-account compromise can't tamper with the audit trail.

### 6. Cost control: every paid service is behind an enable flag

GuardDuty, Security Hub, and especially AWS Config incur ongoing usage-based
cost. To honor the "costs stay capped / destroyable" principle, each is gated by
a boolean variable (`enable_guardduty`, `enable_securityhub`, `enable_config`,
…) defaulting to `true` but flippable to stand the platform down cheaply.
CloudTrail is limited to **management events** by default (the free copy); data
events (S3/Lambda) are opt-in because they can be voluminous and costly.
`docs/layer1-plan.md` carries a per-service cost table.

### 7. Identity model: four permission sets, group-based assignment

Permission sets: **Administrator** (`AdministratorAccess`), **PowerUser**
(`PowerUserAccess`), **ReadOnly** (`ViewOnlyAccess`), **Billing**
(`Billing` + Cost Explorer). Access is granted to **groups**, never directly to
users. Default assignment matrix (tunable via variables):

| Group | management | security | shared-services | workloads-dev | workloads-prod |
|---|---|---|---|---|---|
| `platform-admins` | Administrator | Administrator | Administrator | Administrator | Administrator |
| `developers` | - | - | ReadOnly | PowerUser | ReadOnly |
| `auditors` | ReadOnly | ReadOnly | ReadOnly | ReadOnly | ReadOnly |
| `billing` | Billing | - | - | - | - |

The existing bootstrap admin user joins `platform-admins`. SSO remains the sole
human access path; no IAM users are introduced.

## Consequences

- Layer 1 stacks require the `org` stack's remote state to be readable and the
  `OrganizationAccountAccessRole` to exist in each member account (both true
  post-Layer 0).
- The cross-account assume-role pattern means a failure to assume a member role
  (e.g. the role was renamed) blocks that account's resources, surfaced clearly
  at plan time.
- Delegated administration is sticky: de-registering a delegated admin account
  can require de-configuring the service first. Destroy ordering is documented
  in the plan.
- Enabling Config across all accounts is the largest cost and resource driver;
  it is the most likely knob to turn off for a dormant platform.
- **Organization trusted access must be enabled imperatively.** Terraform's
  `CreateTrail` does *not* auto-enable CloudTrail service access the way the
  console does, so org-service enablement (`aws organizations
  enable-aws-service-access --service-principal <svc>`) is a prerequisite run
  once per service, CloudTrail now, GuardDuty/Security Hub/Config/Access
  Analyzer in the `security` stack. There is no clean standalone Terraform
  resource for it (the only native path is the `aws_organizations_organization`
  singleton, which the `org` stack intentionally reads via a data source rather
  than manages). This is tracked as a candidate to fold into the `org` stack
  later; for now it is documented alongside each stack.
- Deferred workstreams (networking/CI-CD, data, RAG) will each land as their own
  numbered ADR when built.
