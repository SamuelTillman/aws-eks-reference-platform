# ADR-0012: Permission boundaries on privileged principals

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Phase 1 (GitHub OIDC roles) and the human SSO
> permission sets are implemented and verified live (`Administrator`,
> `AdministratorAccess`, `PowerUser` all bounded; policy simulation confirms
> credential-minting / audit-tampering deny while normal work is allowed). The
> stray console-default `AdministratorAccess` set was imported under Terraform in
> the process. Remaining: `permissions_boundary` on the Terraform service roles
> (EKS / Karpenter / Config). This closes the permission-boundary item deferred
> from [ADR-0009](0009-audit-hardening.md).

## Context

The platform's access model is sound in shape (SSO for humans, OIDC for CI, IAM
roles for workloads, zero stored credentials) but the privileged principals are
**unbounded**: each holds `AdministratorAccess` with nothing capping what that
access can become. The self-audit flagged this as the biggest remaining debt.
The three grant sites:

- the mgmt-account **`refplatform-github-actions`** OIDC role (plan + the ADR-0008
  lifecycle button) ([bootstrap](../../terraform/bootstrap/github-oidc.tf)),
- the per-account **`refplatform-github-actions-deploy`** OIDC roles in
  shared-services / dev / prod ([cicd](../../terraform/cicd/oidc-roles.tf)),
- the Identity Center **`Administrator`** permission set for humans
  ([identity](../../terraform/identity/permission-sets.tf)).

`AdministratorAccess` includes the power to **escalate and persist**: mint an IAM
user with long-lived access keys (breaking the zero-credentials invariant), or
create a fresh role with a policy of its choosing. A compromised CI OIDC token,
or a mistaken human, could do either. SCPs help but are org-wide and coarse; a
**permission boundary** caps an individual principal.

**Permission boundary**, briefly: an IAM managed policy attached to a role (or
user) that sets the **maximum** permissions it can ever have. It grants nothing
on its own. Effective permissions are the **intersection** of the principal's
own policy and its boundary. So an `AdministratorAccess` role with a boundary can
still do almost everything, except what the boundary refuses, no matter what
policy is later attached to it.

## Decision

Introduce one reusable **`refplatform-permission-boundary`** policy and attach it
to the privileged principals. Roll out in two phases so the blast radius is
reviewable.

### 1. The boundary policy (a ceiling, not a grant)

A single document, defined once in a shared module
([terraform/modules/permission-boundary](../../terraform/modules/permission-boundary)),
created per-account (a boundary is referenced by an ARN in the same account). It
allows everything, then carves out hard denials:

- **No IAM users or long-lived credentials.** Deny `iam:CreateUser`,
  `CreateAccessKey`, `CreateLoginProfile`, `CreateServiceSpecificCredential`,
  `UploadSSHPublicKey`, `UploadServerCertificate`. This makes the
  zero-stored-credentials rule structural, not just conventional.
- **No going dark on the audit backbone.** Deny stopping/deleting CloudTrail,
  Config, GuardDuty, Security Hub, the same set as the `deny-disable-audit` SCP
  ([ADR-0009](0009-audit-hardening.md)), repeated at the role level so it holds
  even if the SCP is ever detached.
- **No leaving the org / closing the account.**
- **No weakening the boundary itself.** Deny editing or deleting the boundary
  policy, and deny `DeleteRolePermissionsBoundary`.
- **Privilege-escalation guard (the crux).** Deny `iam:CreateRole` and
  `iam:PutRolePermissionsBoundary` unless the request sets **this** boundary
  (`iam:PermissionsBoundary` condition). A bounded principal therefore cannot
  mint an unbounded or weaker-bounded role to climb out of the ceiling.

### 2. Phase 1: the GitHub OIDC roles (this increment)

Attach the boundary to the mgmt `refplatform-github-actions` role
([bootstrap](../../terraform/bootstrap/github-oidc.tf)) and the three
`-deploy` roles ([cicd](../../terraform/cicd/oidc-roles.tf)). These are the
**automated** keys to the kingdom: reachable from CI, so the highest-value target.
The shared module is instantiated once in mgmt (bootstrap) and once per member
account (cicd) so the boundary ARN each role references is account-local.

This does not narrow what the workflows do today: plan, `AssumeRole` into the
member accounts, read state, and run the lifecycle button all remain allowed,
the boundary only removes credential-minting, audit-tampering, and unbounded-role
creation, none of which the workflows perform. (The lifecycle `security`
stand-down disables detectors **through the assumed `OrganizationAccountAccessRole`
in the security account**, not as the bounded OIDC role, so it is unaffected.)

### 3. Phase 2 (next): humans + service roles

- Attach the boundary to the **`Administrator`** (and **`PowerUser`**) Identity
  Center permission sets via `aws_ssoadmin_permissions_boundary_attachment`. A
  permission-set boundary using a customer-managed policy is resolved **per
  target account**, so this requires the boundary policy to exist in every
  account the set is assigned to, hence its own increment.
- Set `permissions_boundary` on the Terraform-created **service roles** (EKS
  cluster / node / Karpenter, Config) so every role the platform creates carries
  it, making the escalation guard total.

### 4. The escape hatch stays

The AWS-managed **`OrganizationAccountAccessRole`** is deliberately **not**
bounded, exactly as it is exempt from the `deny-disable-audit` SCP. It is the
trusted IaC/break-glass path (Terraform assumes it for member-account work). This
guarantees a recovery route: if a boundary change ever over-restricts a bounded
principal, `OrganizationAccountAccessRole` (and mgmt root, the ultimate
break-glass) can still fix it.

## Consequences

- A compromised CI OIDC token can no longer create IAM users/keys, disable the
  audit trail, leave the org, or spawn an unbounded backdoor role. The zero-
  credentials invariant becomes enforced, not just documented.
- **Every future role a bounded principal creates must carry the boundary.**
  Terraform sets `permissions_boundary` explicitly; humans creating roles by hand
  in a bounded session must attach it or be denied (the intended behavior).
- Boundaries are a **ceiling, not a grant**: they never widen access, so they are
  safe to add to an over-broad role now and tighten the role's own policy later
  (the ADR-0005 plan to narrow the deploy roles still stands and now composes
  with this).
- Recovery is always possible via the unbounded `OrganizationAccountAccessRole`,
  so a bad boundary cannot permanently lock the platform out of itself.
- Deferred to phase 2: SSO permission-set boundaries and service-role boundaries.
