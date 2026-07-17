# Architecture Decision Records (ADRs)

## What is an ADR?

An **Architecture Decision Record** is a short document that captures one
significant decision: what we chose, the situation that forced the choice,
and the trade-offs we accepted. Think of it as a note to your future self
(and to anyone forking this repo) answering *"why on earth is it built this
way?"*, before someone has to reverse engineer the answer from the code.

Each ADR is deliberately small and follows the same shape:

- **Context**, the situation and constraints that made a decision necessary
- **Decision**, what we actually chose to do
- **Rationale / Consequences**, why, and what we gave up or took on as a result

A **Status** (Proposed → Accepted → Superseded) shows whether a decision is
current. Decisions aren't deleted when they change: we add a new ADR that
supersedes the old one, so the *reasoning history* stays intact. That trail,
seeing not just what's true today but how the thinking evolved, is the whole
point.

Files are numbered sequentially (`0001`, `0002`, …) and never renumbered, so a
reference like "ADR-0002" always points at the same decision.

Want the background on the format? See Michael Nygard's original write-up:
<https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>

## Log

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-why-this-platform-exists.md) | Why this platform exists | Accepted |
| [0002](0002-raw-organizations-over-control-tower.md) | Raw AWS Organizations + Terraform over Control Tower | Accepted |
| [0003](0003-layer-0-deployment-decisions.md) | Layer 0 deployment decisions (region, backend, CI, SCP reconciliation) | Accepted |
| [0004](0004-layer-1-landing-zone-architecture.md) | Layer 1 landing zone architecture (cross-account model, delegated admin, identity) | Accepted |
| [0005](0005-cicd-foundation.md) | CI/CD foundation, per-account OIDC deploy roles, central ECR, prod approval gate | Accepted |
| [0006](0006-network-architecture.md) | Network architecture, centralized-egress hub-and-spoke with Transit Gateway | Accepted |
| [0007](0007-eks-cluster-foundation.md) | EKS cluster foundation, dev cluster, VPC CNI, managed node group, access entries | Accepted |
| [0008](0008-cicd-lifecycle-teardown-rebuild.md) | Push-button teardown/rebuild (CI-driven apply/destroy lifecycle) + budget alarms | Accepted |
| [0009](0009-audit-hardening.md) | Audit hardening: preventive SCP, S3 Object Lock, TLS-only, Config conformance pack, IMDSv2 | Accepted |
