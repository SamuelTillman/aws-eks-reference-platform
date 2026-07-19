# ADR-0014: Admission policy with Kyverno

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Implemented as a GitOps component
> ([ADR-0010](0010-gitops-argocd.md)): the Kyverno engine plus a small starter set
> of cluster policies.

## Context

Nothing yet governs what can run on the cluster. Any pod, however misconfigured
(privileged, `:latest` image, no resource requests, running as root), is admitted.
A security-reference platform needs a **policy engine** at the admission gate to
codify guardrails, the Kubernetes-layer analogue of the SCPs and permission
boundaries already guarding the AWS layer.

**Kyverno**, briefly: a Kubernetes-native policy engine that runs as an admission
webhook. Policies are plain Kubernetes resources (`ClusterPolicy` / `Policy`), no
new language to learn (unlike OPA/Gatekeeper's Rego). A policy can **validate**
(allow/deny/audit an incoming object), **mutate** (patch defaults in), or
**generate** (create companion objects). It fits this platform's "everything is a
manifest in Git" model exactly.

## Decision

Run **Kyverno** as the cluster admission-policy engine, delivered by GitOps, with
a small, deliberately safe starter policy set.

### 1. GitOps, split engine + policies (sync-wave ordering)

Same shape as Karpenter ([ADR-0011](0011-karpenter-autoscaling.md)):

- `gitops/apps/kyverno.yaml`, the Kyverno Helm chart (pinned) into a `kyverno`
  namespace, at **sync-wave 2**, so its CRDs (`ClusterPolicy`, ...) exist first.
- `gitops/apps/kyverno-policies.yaml`, at **sync-wave 3**, sourcing the
  `ClusterPolicy` manifests from `gitops/kyverno/` (kept out of `apps/` so the
  root app does not apply the CRs before their CRDs exist).

### 2. Starter policies: mostly Audit, one Enforce, system namespaces exempt

The starters encode common best practices. **Crucially, they run in `Audit` mode
by default** (report violations, do not block) so they cannot brick platform
components, node-exporter, Karpenter, and others legitimately need privileged /
hostPath / host-namespace access, and a blanket `Enforce` would break them. All
policies also **exclude the platform namespaces** (`kube-system`, `kyverno`,
`karpenter`, `monitoring`, `argocd`).

- `disallow-latest-tag` (**Enforce**), block images with no tag or `:latest`, in
  non-system namespaces. This is the one enforcing policy: reproducible,
  low-risk (nothing legitimate here uses `:latest` outside system namespaces), and
  it makes the gate demonstrable, a `nginx:latest` pod in `default` is rejected.
- `require-requests-limits` (Audit), workloads should declare resource
  requests/limits (also what lets Karpenter bin-pack well).
- `disallow-privileged-containers` (Audit), flag privileged containers.
- `require-run-as-nonroot` (Audit), flag containers not forced to run as non-root.

Promoting the Audit policies to Enforce (with the right exclusions) is the
production step, deliberately left as a knob rather than a default so the starter
set is safe to apply unattended.

### 3. Sized for a small cluster

The engine runs with modest footprint on the existing nodes; like every component
it consolidates away with the cluster on teardown.

## Consequences

- The cluster now has an admission gate: policy is code in Git, versioned and
  reviewable, matching the AWS-layer guardrails. `disallow-latest-tag` actively
  enforces; the rest report, giving a compliance view without breaking workloads.
- The Audit-first default is a deliberate safety choice; the value ramps as
  policies are promoted to Enforce with per-namespace exclusions once real
  workloads exist.
- Kyverno policy reports (`PolicyReport` objects) become a data source a future
  observability/compliance dashboard can surface, composing with
  [ADR-0013](0013-observability.md).
- Deferred: promoting starters to Enforce, mutate/generate policies (e.g.
  inject default securityContext, generate NetworkPolicies), and wiring policy
  reports into Grafana.
