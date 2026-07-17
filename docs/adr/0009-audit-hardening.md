# ADR-0009: Audit hardening (preventive guardrails + immutable evidence)

**Status:** Accepted · **Date:** 2026-07

## Context

A Well-Architected + audit-readiness review (see
[layer2-issues.md](../layer2-issues.md) and the assessment that prompted this
ADR) found the platform strong on **detective** controls and encryption (org
CloudTrail with log-file validation, delegated-admin separation, complete Config
recording, CMK encryption) but weak on **preventive** controls. The gaps that a
real audit flags first:

1. No SCP stops anyone disabling the audit backbone
   (`cloudtrail:StopLogging`, `config:StopConfigurationRecorder`,
   `guardduty:DeleteDetector`, ...).
2. Audit logs are versioned but not immutable (no S3 Object Lock / WORM).
3. No bucket enforces TLS-only (`aws:SecureTransport`).
4. AWS Config records but evaluates nothing (0 rules / conformance packs).
5. EKS nodes do not enforce IMDSv2 or explicit EBS encryption.

Plus a standing least-privilege debt (four `AdministratorAccess` roles), handled
in a separate increment.

## Decision

Harden in the layer that owns each control. This ADR covers the five P0s; the
permission-boundary work is deferred to its own increment.

### 1. Audit-protection SCP (`org/scps.tf`)

A fourth guardrail SCP denying the actions that disable or tear down the audit
and security services (CloudTrail, Config, GuardDuty, Security Hub), attached to
all three OUs like the existing set.

**Exempt the `OrganizationAccountAccessRole`** (`aws:PrincipalArn ArnNotLike
.../OrganizationAccountAccessRole`). Rationale: Terraform and the gated
[ADR-0008](0008-cicd-lifecycle-teardown-rebuild.md) lifecycle workflow act
through that role, including the deliberate `security` stand-down. Everyone else
(workload roles, SSO humans, app credentials, a compromised non-IaC principal)
is denied. This blocks casual/malicious tampering without breaking the trusted,
CloudTrail-logged IaC path. Note this is a real trade: the IaC path can still
tear down the services. The **hard** immutability of the evidence comes from
Object Lock, below, which not even root can bypass.

### 2. Immutable audit evidence: S3 Object Lock (`logging/`, later `config/`)

Enable **Object Lock in COMPLIANCE mode** with a default retention on the
CloudTrail archive bucket, so log objects cannot be deleted or overwritten by
anyone (including root) for the retention window. This is the single
highest-value audit control.

**Migration nuance:** Object Lock's enablement is create-time in the AWS provider
(`aws_s3_bucket.object_lock_enabled` forces replacement), and the audit bucket
already exists with logs. We will NOT let Terraform replace it (that destroys the
logs). Path: enable Object Lock on the existing versioned bucket out of band
(`aws s3api put-object-lock-configuration`), then manage the default-retention
rule via `aws_s3_bucket_object_lock_configuration` and set
`object_lock_enabled = true` on the bucket resource so state matches without a
replace. Executed deliberately with the plan shown; not a blind apply.

### 3. TLS-only bucket policies (all buckets)

Add a `Deny` on `s3:*` when `aws:SecureTransport = false` to every bucket policy,
starting with the audit buckets (CloudTrail, Config), then state and flow-log
buckets. Enforces encryption in transit.

### 4. Config conformance pack (`config/`)

Deploy an org conformance pack (CIS / AWS FSBP baseline) from the delegated-admin
security account, turning "recording" into continuously-evaluated evidence.
Behind an `enable_*` flag for cost.

### 5. IMDSv2 + encrypted EBS on EKS nodes (`eks/nodes.tf`)

Attach a launch template to the managed node group with
`metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }`
and encrypted root EBS (CMK). Closes the node-role-theft path (pod/SSRF to IMDS)
and guarantees node-local encryption. Also add a `validation` block rejecting
`0.0.0.0/0` in `public_access_cidrs`.

### Sequencing

The SCP and TLS-only policies are additive and land first (this increment).
Object Lock (bucket migration), the conformance pack, and the node launch
template follow as their own deliberate applies. Org-level SCP changes are
plan-shown before apply per the hard rules.

## Consequences

- The audit trail becomes genuinely tamper-resistant: preventive SCP stops
  disabling it, Object Lock makes the historical evidence WORM-immutable, and
  TLS-only closes in-transit gaps.
- The `OrganizationAccountAccessRole` exemption keeps the teardown button and all
  IaC working; the security story is that the trusted IaC path is auditable and
  the evidence is immutable regardless.
- Config gains real compliance evidence via the conformance pack.
- EKS nodes meet the IMDSv2 / encrypted-volume bar before the cluster is
  deployed.
- Remaining hardening (permission boundaries on the four admin roles, backup/DR,
  incident-response alerting, tag policy, break-glass) is tracked for follow-up
  increments.
