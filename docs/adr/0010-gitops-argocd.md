# ADR-0010: GitOps delivery with ArgoCD

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Decision only. This ADR fixes how platform software
> is delivered to the cluster; the ArgoCD install and the first managed apps are
> the next increment.

## Context

The `refplatform-dev` cluster is live ([ADR-0007](0007-eks-cluster-foundation.md)),
but it is bare: just the CNI, DNS, kube-proxy, and Pod Identity agent. The rest of
the Layer 2 platform (Karpenter, Cilium, Prometheus/OpenTelemetry, Kyverno,
Backstage) still needs a way to get onto the cluster. ADR-0007 committed to
delivering all of it by **GitOps** rather than more Terraform. This ADR fixes the
GitOps mechanism.

**GitOps**, briefly for readers new to it: the desired state of the cluster lives
as manifests in Git, and an in-cluster agent continuously reconciles the cluster
to match Git. Git is the single source of truth; you change the cluster by merging
a commit, not by running `kubectl apply` by hand. That gives an audit trail, easy
rollback, and drift correction for free.

## Decision

Use **ArgoCD** as the in-cluster GitOps agent, bootstrapped by Terraform and then
self-driving via the app-of-apps pattern.

### 1. Bootstrap with Terraform, then hand off to Git

A new `terraform/argocd` stack installs ArgoCD via the Helm provider (state key
`argocd/terraform.tfstate`). This is the one piece Terraform owns; everything
after it is Git-driven. The chicken-and-egg (something has to install the thing
that installs everything) is resolved by keeping the Terraform footprint to just
ArgoCD itself plus a single **root Application**.

### 2. App-of-apps

**App-of-apps**: the Terraform-managed root Application points at a `gitops/`
directory in this repo; that directory contains one ArgoCD `Application` per
platform component (Karpenter, Cilium, observability, ...). Adding a component to
the platform becomes "add an Application manifest under `gitops/` and merge",
not a Terraform change. Each later increment lands as one or more Applications.

- **Layout:** `gitops/root/` (the root app, referenced by Terraform) and
  `gitops/apps/` (child Applications). Components self-organize from there.
- **Source:** this **public** repo, read-only. Because the repo is public, ArgoCD
  reads it with no credentials and no deploy key. A private fork would add a
  read-only deploy token; nothing else changes.

### 3. Provider auth (cross-account, and a known exec quirk)

The Helm and Kubernetes providers reach the cluster in `workloads-dev` the same
way the rest of the platform does: assume that account's
`OrganizationAccountAccessRole`, then authenticate to EKS. Authentication uses the
`aws eks get-token` exec plugin. Note the workstation quirk logged in
[layer2-issues.md](../layer2-issues.md) #4: the `--role-arn` form of the exec can
hang, so the stack authenticates with **already-assumed ambient credentials**
(assume the role, then run without `--role-arn`) rather than delegating the assume
to the exec plugin.

### 4. Reaching the UI on a private-first cluster

The cluster endpoint is private with a CIDR-restricted public path, and there is
no ingress controller yet. So the ArgoCD server stays a `ClusterIP` service and is
reached by **`kubectl port-forward`** for now. A proper internal load balancer or
ingress arrives with the load-balancer/mesh increment; exposing ArgoCD publicly is
deliberately not done here.

### 5. Authentication and sync policy

- **Admin:** ~~the built-in ArgoCD admin (initial password in an auto-generated
  in-cluster secret) to start~~. **Superseded by
  [ADR-0015](0015-dashboard-access-no-second-credential.md):** the local admin
  account is disabled entirely and access goes through the kubeconfig-backed
  `argocd admin dashboard` / `--core`, so no ArgoCD password exists at all.
- **Sync:** child apps run **automated sync with self-heal and prune** so the
  cluster always matches Git; drift is corrected and deleted manifests are removed.

### 6. Cost and teardown

ArgoCD runs on the existing system node group, so it adds **no new nodes** and
negligible cost. The `argocd` stack becomes a lifecycle target
([ADR-0008](0008-cicd-lifecycle-teardown-rebuild.md)) so it tears down and rebuilds
with the rest.

## Consequences

- Every platform component after this lands as a Git-managed `Application`, not a
  Terraform stack. Terraform's role shrinks to the cluster, ArgoCD, and the root
  app.
- The root Application is the single Terraform-managed handle on the whole GitOps
  tree; losing it does not delete running apps, but re-bootstrapping restores the
  management link.
- The private-first UI (port-forward) is a deliberate early-stage trade; public or
  SSO-gated access is a later, deliberate step.
- GitOps gives an audit trail and rollback for platform changes, reinforcing the
  same "everything is code, nothing by hand" posture the infrastructure already
  follows.
- Deferred to their own increments: SSO for ArgoCD, ingress/LB exposure, and the
  actual component Applications (Karpenter first, then Cilium, observability,
  Kyverno, Backstage).
