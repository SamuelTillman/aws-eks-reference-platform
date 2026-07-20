# ADR-0016: Platform secrets with External Secrets + AWS Secrets Manager

**Status:** Proposed · **Date:** 2026-07

> **Implementation status:** Planned increment, not built. Scoped here so the
> decision and its rationale exist before the first workload needs a secret.

## Context

The platform has a strong story for **identities** (Identity Center for humans,
GitHub OIDC for CI, Pod Identity for workloads, boundaries over all of it) and no
story at all for **secrets**. That gap surfaced with Grafana
([ADR-0015](0015-dashboard-access-no-second-credential.md)): its admin password
had to go somewhere, and the stopgap is a `random_password` in Terraform state
delivered as a Kubernetes Secret. That works for one password owned by the
platform, and it does not generalize:

- It only covers secrets **Terraform generates**, not ones that already exist
  (third-party API keys, database credentials, license tokens).
- There is no **rotation**, no audit trail of who read what, and no way to share a
  secret across accounts or clusters.
- Every future workload would reinvent its own delivery mechanism.

Any real workload on this cluster will need secrets. This decides how, before the
answer gets improvised per app.

## Decision (proposed)

Adopt **External Secrets Operator (ESO)** reading from **AWS Secrets Manager**,
authenticated by **EKS Pod Identity**.

### 1. Why this combination

- **Pod Identity is already the platform's workload-IAM mechanism**
  ([ADR-0007](0007-eks-cluster-foundation.md)). ESO gets an IAM role with no IRSA
  annotations and no stored credentials, matching the existing grain exactly.
- **Secrets Manager is managed and survives teardown.** The platform tears down to
  near-zero and rebuilds from code
  ([ADR-0008](0008-cicd-lifecycle-teardown-rebuild.md)); secrets must outlive the
  cluster. Secrets Manager does that for roughly $0.40 per secret per month, with
  native rotation and CloudTrail-audited access.
- **ESO ships as a GitOps component** like everything else
  ([ADR-0010](0010-gitops-argocd.md)): a `ClusterSecretStore` pointing at Secrets
  Manager, plus an `ExternalSecret` per consumer that materializes a normal
  Kubernetes Secret. Workloads consume Secrets the ordinary way and stay unaware
  of the backend.

### 2. Why not HashiCorp Vault

Not a knock on Vault, it is the wrong fit for **this** platform's shape. Vault
needs persistent storage and an init/unseal lifecycle. On a cluster deliberately
destroyed and rebuilt on demand, Vault's state either dies with the cluster
(losing the secrets it exists to protect) or requires surviving EBS/S3 plus KMS
auto-unseal, adding real operational surface to protect a handful of values. Vault
earns its keep with **dynamic/leased credentials, multi-cloud, or complex policy**,
none of which is true here yet. Revisit if that changes.

### 3. Why not SSM Parameter Store

A legitimate cheaper alternative (SecureString parameters are effectively free)
and ESO supports it. Secrets Manager is chosen for **built-in rotation**,
cross-account resource policies, and its clearer audit story. A fork optimizing
for cost can point the same `ClusterSecretStore` at Parameter Store with a
one-line change.

### 4. First consumer

Grafana. Its `random_password` stopgap from ADR-0015 is replaced by a Secrets
Manager secret plus an `ExternalSecret`, proving the pattern end to end on
something low-risk before real workloads depend on it.

## Consequences

- The platform gains a general secrets story: rotation, IAM-gated retrieval, an
  audit trail, and secrets that outlive the cluster.
- Secrets stop living in Terraform state, removing the ADR-0015 trade-off.
- Adds a component and a small recurring cost (~$0.40 per secret per month) that
  does **not** tear down to zero. Deliberate: secrets surviving teardown is the
  point.
- **This still does not make Grafana credential-free.** Grafana OSS mandates an
  admin user; ESO makes that credential well-managed and rotatable, not absent.
  Only Amazon Managed Grafana (native Identity Center) removes it entirely, at
  per-user cost and the loss of self-hosting.
- Deferred until a workload actually needs it, or until Grafana's stopgap becomes
  worth replacing.
