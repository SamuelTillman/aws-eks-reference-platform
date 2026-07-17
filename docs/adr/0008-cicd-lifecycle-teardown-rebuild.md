# ADR-0008: Push-button teardown / rebuild (CI-driven lifecycle)

**Status:** Accepted · **Date:** 2026-07

## Context

The platform carries a standing cost even when idle. With Layer 1 deployed and no
workload on top, the meters are running: 3 NAT gateways plus a Transit Gateway
(centralized egress, [ADR-0006](0006-network-architecture.md)) are roughly
$200/month, and the paid security services add ~$15-40/month (Security Hub is the
bulk; GuardDuty is ~$0.03/month at this activity; AWS Config is low at idle but
its per-item recording rises with infrastructure churn). No EKS cluster is
deployed yet, so that egress fabric is idling with nothing using it.

The repo already promises "costs stay capped, destroyable" and "if it can't be
rebuilt from this repo, it doesn't belong in this repo"
([README](../../README.md)). Until now that meant running `terraform destroy`
locally per stack. We want it to be one action, ideally from GitHub Actions, so
the expensive layers can be stood down between work sessions and rebuilt on
demand.

This crosses a line the platform has held so far: **CI has been plan-only**
(a [hard rule](../../CLAUDE.md): never apply an unshown plan). A teardown button
means CI runs `terraform apply` and `terraform destroy`. That decision needs
recording, with guardrails, which is what this ADR does. (We flagged the
"CI-driven apply" decision as its own increment back in
[ADR-0005](0005-cicd-foundation.md); this is it, scoped to lifecycle.)

## Decision

A single manually-triggered workflow, `.github/workflows/platform-lifecycle.yml`
(`workflow_dispatch` only), that can `apply` or `destroy` the **rebuildable**
layers. Inputs:

| Input | Values | Meaning |
|---|---|---|
| `stack` | `networking`, `eks`, `security` | Which layer to act on |
| `action` | `apply`, `destroy` | Create/rebuild, or tear down |
| `confirm` | free text | Must equal `stack` to run a `destroy` (fat-finger guard) |

Semantics:

- `networking` / `eks`: `apply` runs `terraform apply`; `destroy` runs
  `terraform destroy`. These are the ~$200/month cost drivers and the future
  cluster.
- `security`: this stack is toggled by `enable_*` flags, not destroyed (a real
  destroy would tear down delegated-administration wiring). So for `security`,
  `destroy` means **stand down** (apply with `enable_guardduty`,
  `enable_securityhub`, `enable_access_analyzer` set to `false`) and `apply`
  means **restore** (flags back to `true`). Kept as a separate, deliberate toggle
  rather than coupled to routine networking cycling, because Config's per-item
  recording makes frequent churn work against the savings.

### Guardrails (how this stays safe despite CI applying)

1. **Manual only.** `workflow_dispatch`; never runs on push or PR.
2. **Typed confirmation.** A `destroy` aborts unless `confirm` exactly equals the
   `stack` name.
3. **Plan is shown.** Every run prints `terraform plan` (or `plan -destroy`)
   before acting, preserving the spirit of "never apply an unshown plan": the
   human dispatching the run, with the plan in the log, is the approval.
4. **Environment gate.** The job runs in a GitHub **Environment**
   (`platform-lifecycle`) so a required reviewer can be added in repo settings as
   a second human gate. (Until a reviewer is configured the environment simply
   runs; configuring it is a documented setup step.)
5. **Foundation is off-limits.** The `stack` choice only ever offers the
   rebuildable layers. `bootstrap`, `org`, `identity`, and `logging` (the state
   bucket, the org accounts and SCPs, and the audit archive) are never targets.
6. **Serialized.** A `concurrency` group per stack prevents a simultaneous
   apply and destroy of the same stack.

The workflow reuses the existing `refplatform-github-actions` OIDC role (mgmt
`AdministratorAccess`, assumes each member account's
`OrganizationAccountAccessRole`) and the masked `TF_STATE_BUCKET` secret, exactly
like the plan workflow.

### Budget alarms (companion)

A new `terraform/budgets` stack (mgmt/payer account) creates a monthly cost
budget with email notifications at every **$50 of actual spend** ($50, $100, ...,
up to a configurable ceiling). This is the cost-visibility half of the same goal
and does not depend on Cost Explorer being enabled. The alert email lives in
gitignored tfvars.

## Consequences

- Standing cost can be driven to near-zero on demand and rebuilt from code, making
  the "destroyable" promise real and one click away.
- CI now holds apply/destroy power over the rebuildable layers. The blast radius
  is bounded by the stack allow-list, the typed confirm, the shown plan, and the
  environment reviewer. This is a deliberate, narrow exception to plan-only CI,
  not a general opening of auto-apply.
- Standing down `security` reduces audit/threat coverage while it is off; it is a
  conscious idle-period trade, not a default. Restoring is one `apply`.
- AWS Config has no enable flag and is not a lifecycle target; its idle cost is
  low, and its churn cost is inherent to cycling infrastructure. Frequent
  teardown/rebuild will show up as Config item-recording spend.
- A forker gets the same button; the OIDC role and immutable-ID subject handling
  ([layer2-issues.md](../layer2-issues.md) #2) already make it forkable.
