# Layer 1 build plan: landing zone foundation

Companion to [ADR-0004](adr/0004-layer-1-landing-zone-architecture.md). Scope:
the identity / logging / security foundation. Deferred workstreams
(networking + CI/CD, data pipeline, Bedrock RAG) are tracked in ADR-0004 and get
their own plans.

## Build order (dependency-driven)

| Step | Stack | Blast radius | Why this order |
|------|-------|--------------|----------------|
| 1 | `terraform/identity` | management only | No cross-account writes; safe first exercise of the remote-state read pattern |
| 2 | `terraform/logging` | management + `security` + per-account | Audit backbone; other services deliver into it |
| 3 | `terraform/security` | management + `security` | GuardDuty/Security Hub/Access Analyzer; benefits from logging existing |

Each stack: `init -backend-config=backend.hcl` → `validate` → `plan` → **review +
approve** → `apply`. Same partial-backend, gitignored-tfvars discipline as
Layer 0.

## Step 1: `terraform/identity`

Management-account only (Identity Center lives there). Reads `org` remote state
for account IDs.

- **Permission sets:** Administrator (`AdministratorAccess`), PowerUser
  (`PowerUserAccess`), ReadOnly (`ReadOnlyAccess`), Billing (`job-function/Billing`)
- **Groups:** `platform-admins`, `developers`, `auditors`, `billing`
- **Assignments:** the matrix in ADR-0004 §7, expressed as a Terraform `for_each`
- **Membership:** optional `platform_admin_usernames` var wires existing SSO users
  into `platform-admins` (default empty)

Verify: `aws sso-admin list-permission-sets`, `aws identitystore list-groups`,
and confirm assignments resolve in the Identity Center console.

## Step 2: `terraform/logging`

Delivered in two increments to keep each plan reviewable:

**2a, CloudTrail audit backbone (done):**
- **Org CloudTrail** (`is_organization_trail = true`) in management, management
  events only by default (data events opt-in via `enable_data_events`)
- **Central log bucket** in `security`: KMS-encrypted, versioned, public access
  blocked, bucket policy scoped to the org trail via `aws:SourceArn`
- **Prerequisite:** CloudTrail trusted access enabled once with
  `aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com`
  (Terraform does not auto-enable it, see ADR-0004 consequences)

**2b, AWS Config (follow-up):**
- Per-account recorder + delivery channel (via account provider aliases) →
  central bucket; **organization aggregator** in `security`
- Behind `enable_config` (the heaviest cost driver); reviewed as its own plan

Verify: `aws cloudtrail get-trail-status` (`IsLogging: true`), object landing in
the bucket, later `aws configservice describe-configuration-aggregators`.

## Step 3: `terraform/security`

- **GuardDuty:** delegate admin → `security`; detector + org auto-enable (`ALL`)
- **Security Hub:** delegate admin → `security`; enable AWS FSBP + CIS standards;
  org auto-enable
- **IAM Access Analyzer:** `ORGANIZATION` analyzer in `security`
- Cost gates: `enable_guardduty`, `enable_securityhub`

Verify: `aws guardduty list-detectors`, `aws securityhub get-enabled-standards`,
`aws accessanalyzer list-analyzers`.

## Cost table (us-east-1, order-of-magnitude, for a dormant reference platform)

| Service | Cost driver | Dormant-platform note |
|---|---|---|
| CloudTrail | 1st mgmt-events copy free; data events $/100k | Keep data events off unless debugging |
| AWS Config | ~$0.003 / config item + rule evals | **Largest variable cost**; first knob to disable |
| GuardDuty | events/log volume; 30-day free trial | Low on an idle org; scales with activity |
| Security Hub | $/check + $/finding after free tier | Low idle; grows with resources |
| S3/KMS (logs) | storage + request + key | Negligible idle |

All paid services are behind `enable_*` flags (default `true`) so the platform
can be stood down to near-zero and rebuilt from code.

## Destroy ordering

Reverse of build (`security` → `logging` → `identity`). De-configure org
services before de-registering their delegated admin (GuardDuty/Security Hub org
configuration must be removed before the admin account is de-registered).
