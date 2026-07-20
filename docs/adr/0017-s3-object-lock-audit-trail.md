# ADR-0017: S3 Object Lock on the audit trail

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Implemented and verified live. Closes the last
> deferred item from [ADR-0009](0009-audit-hardening.md).

## Context

The platform already makes the audit trail hard to *switch off*: an organization
CloudTrail with log-file validation, a write-isolated bucket in the security
account, and a `deny-disable-audit` SCP blocking `StopLogging`/`DeleteTrail` and
the equivalent Config/GuardDuty/Security Hub calls
([ADR-0004](0004-layer-1-landing-zone-architecture.md),
[ADR-0009](0009-audit-hardening.md)).

None of that protects the **log data itself**. An attacker (or a mistake) with
sufficient S3 permissions could still delete the objects. SCPs guard the control
plane; nothing guarded the bytes. That is the difference between tamper-**evident**
and tamper-**resistant**, and it is why ADR-0009 listed Object Lock as required
and then deliberately deferred it: enabling it is **irreversible**, and doing it
wrong risks destroying the archive it exists to protect.

**S3 Object Lock**, briefly: write-once-read-many (WORM) for S3. An object version
under retention cannot be deleted or overwritten until its retention expires, not
by an admin, not by the bucket owner. It requires versioning and cannot be
disabled once enabled on a bucket.

## Decision

Enable **Object Lock in GOVERNANCE mode with a 7-day default retention** on the
audit bucket, and deny the bypass permission to everyone except one break-glass
path.

### 1. Enabled in place, without replacing the bucket

Applied as a standalone `aws_s3_bucket_object_lock_configuration` resource rather
than the bucket's create-time `object_lock_enabled` argument. That distinction is
the whole safety story: setting the create-time argument on an existing bucket
forces Terraform to **replace** it, destroying the archive. The separate resource
calls `PutObjectLockConfiguration` on the live bucket, which AWS permits because
versioning was already on. The plan was checked for exactly this before applying
(`1 to add, 1 to change, 0 to destroy`).

**Scope:** Object Lock applies to objects written **after** enablement. The ~15k
objects already present carry no retention. Acceptable: the control protects the
trail going forward, and back-filling retention on historical objects is a
separate, deliberate operation.

### 2. GOVERNANCE, not COMPLIANCE

- **COMPLIANCE** makes an object undeletable by *anyone, including the root user*,
  with no escape and no way to shorten the period. It is the right answer under a
  regulator.
- On a **public, forkable reference platform** it is a trap: a fork that enables it
  with a long period can never clean up, and pays to store data it cannot remove.

So: GOVERNANCE, which is bypassable only with `s3:BypassGovernanceRetention`.

### 3. The bucket policy is what gives GOVERNANCE teeth

GOVERNANCE alone would be weak here, since any `AdministratorAccess` principal
holds `s3:*` and could simply bypass it. The bucket policy therefore **denies**
`s3:BypassGovernanceRetention`, `s3:DeleteObjectVersion`, and
`s3:PutObjectRetention` to every principal **except**
`OrganizationAccountAccessRole`, the same exemption pattern the
`deny-disable-audit` SCP uses.

Net effect: for the SSO admin, CI, and every workload role, the archive behaves
like COMPLIANCE. One documented, audited break-glass path remains for deliberate
cleanup. Both mode and retention are variables, so a regulated fork sets
`log_object_lock_mode = "COMPLIANCE"` and a longer period without touching code.

### 4. Retention deliberately short

7 days by default. CloudTrail writes continuously and the logging stack is never a
teardown target, so every object is immutable for a week. Long enough to
demonstrate and rely on, short enough that a fork is not stuck with undeletable
data. A real audit trail would use 365+ days.

## Consequences

- The audit trail is now tamper-**resistant**, not just tamper-evident. Deleting
  recent CloudTrail data requires the break-glass role, and that action is itself
  logged.
- **Verified live**, not assumed: a probe object written after enablement
  inherited `GOVERNANCE` retention automatically; deleting its version failed with
  *"Access Denied because object protected by object lock"*; the break-glass path
  (OAAR + `--bypass-governance-retention`) then removed it cleanly.
- **Irreversible.** Object Lock cannot be disabled on this bucket. A full teardown
  of the logging stack now requires waiting out retention or using break-glass;
  `force_destroy` alone will not do it.
- The `enable_log_object_lock` flag only guards *initial* enablement. Setting it
  false later removes the Terraform configuration but does **not** disable Object
  Lock on the bucket, AWS provides no such operation.
