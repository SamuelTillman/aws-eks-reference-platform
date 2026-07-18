# ADR-0011: Node autoscaling with Karpenter, delivered by GitOps

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Implemented. This is the first real platform
> component delivered through the GitOps pipeline stood up in
> [ADR-0010](0010-gitops-argocd.md): the cluster stops being a fixed two-node
> tier and starts scaling compute on demand.

## Context

`refplatform-dev` runs a small, fixed **system** managed node group (2 spot
nodes, [ADR-0007](0007-eks-cluster-foundation.md)) that hosts cluster-critical
add-ons and, per that ADR, "in a later increment, the Karpenter controller."
Nothing yet scales workload capacity: schedule a pod that does not fit and it
sits `Pending`. The platform needs an autoscaler, and it needs to be the
**cheap, functional** kind: fast, bin-packing, spot-first, and able to
consolidate idle capacity back down so an idle cluster costs almost nothing.

**Karpenter**, briefly for readers new to it: an open-source Kubernetes node
autoscaler (from AWS) that watches for unschedulable pods and launches
right-sized EC2 instances directly, then removes them when they are empty or
underutilized. Unlike the older **Cluster Autoscaler**, which scales fixed-shape
node groups (Auto Scaling Groups) up and down, Karpenter has no node groups: it
picks the instance type, size, and Availability Zone per batch of pending pods
from the whole EC2 menu. That yields tighter bin-packing, faster scale-up, and
much better spot usage.

### Why Karpenter over Cluster Autoscaler here

- **Bin-packing, not group-shaped.** Cluster Autoscaler can only add another node
  of a group's fixed shape; Karpenter chooses the cheapest instance that fits the
  actual pending pods. For a mixed AI/GPU roadmap (very different pod shapes) that
  flexibility matters.
- **Consolidation.** Karpenter actively repacks and deletes underutilized nodes,
  the single biggest lever for "cheap when idle."
- **Spot-native.** First-class spot support with interruption handling, so the
  default capacity is the cheapest.

## Decision

Run **Karpenter** as the cluster's node autoscaler. Split delivery along the same
seam the rest of the platform uses: **AWS prerequisites in Terraform** (they need
IAM, an SQS queue, and cloud tags, and must be torn down with the cluster),
**Karpenter itself and its provisioning config in Git** (it is a cluster workload,
so ArgoCD owns it, [ADR-0010](0010-gitops-argocd.md)).

### 1. AWS prerequisites live in the `eks` Terraform stack

Added as `terraform/eks/karpenter.tf` (no new stack: these resources are
cluster-scoped and share the cluster's lifecycle and teardown target):

- **Controller IAM role via Pod Identity.** The controller authenticates with the
  **EKS Pod Identity** agent already installed in ADR-0007 (not IRSA). A role is
  associated to the `karpenter` service account and carries Karpenter's documented
  controller policy: describe/run/terminate EC2, read SSM for AMI resolution,
  pricing, and a tightly scoped `iam:PassRole` for the node role only.
- **Dedicated node IAM role + access entry.** Karpenter-launched nodes assume
  their **own** role (same four managed policies as the system node role) and join
  the cluster through an explicit `EC2_LINUX` **access entry** (API auth mode,
  ADR-0007). Kept separate from the system managed-node-group role so the two
  capacity sources are decoupled and legible.
- **Interruption handling: SQS + EventBridge.** A single SQS queue receives spot
  interruption, instance rebalance, instance-state-change, and scheduled-change
  events via four EventBridge rules. Karpenter drains and replaces a node
  *before* AWS reclaims it, instead of taking a hard spot kill. The queue and
  rules cost effectively nothing.
- **EC2 Spot service-linked role.** Created explicitly. On a fresh account the
  `AWSServiceRoleForEC2Spot` SLR may not exist yet, and its absence makes the very
  first spot `RunInstances` fail. Same defensive pattern as the Access Analyzer
  SLR in [layer1-issues.md](../layer1-issues.md) #2.
- **Discovery tags.** The dev VPC private subnets and the cluster security group
  are tagged `karpenter.sh/discovery = refplatform-dev`. Karpenter's
  `EC2NodeClass` selects subnets and security groups by this tag rather than
  hardcoded IDs, so nothing account-specific leaks into Git.

### 2. Karpenter itself is a GitOps Application

Under `gitops/apps/`, picked up automatically by the app-of-apps root:

- **`karpenter.yaml`**, an ArgoCD `Application` installing the Karpenter Helm
  chart (`oci://public.ecr.aws/karpenter/karpenter`, pinned) into the `karpenter`
  namespace, at **sync-wave 0** so the CRDs (`NodePool`, `EC2NodeClass`) exist
  before anything references them.
- **`karpenter-nodepool.yaml`**, an `Application` sourcing the raw `NodePool` +
  `EC2NodeClass` manifests at **sync-wave 1**. Splitting the CRD-installing chart
  from the custom resources that use those CRDs avoids ArgoCD's
  "CRD not found at apply time" ordering trap.

### 3. Provisioning shape: cheap by default, bounded by guardrails

The default `NodePool`:

- **Spot only, `amd64`,** general-purpose families (`c`, `m`, `r`), newer
  generations. Broad instance choice is what lets Karpenter find the cheapest fit.
- **Consolidation `WhenEmptyOrUnderutilized`** so idle capacity is actively
  repacked and removed, not just scaled on empty.
- **A CPU `limit`** on the pool as a cost blast-radius cap: a runaway workload
  cannot scale the account into oblivion. It is a deliberately low reference-sized
  ceiling, meant to be raised knowingly.
- **`expireAfter` (30 days)** so nodes are recycled for a fresh, patched AMI.
- **`EC2NodeClass`:** AL2023, the Karpenter node role, tag-based subnet/SG
  discovery, an **encrypted gp3** root volume, and **IMDSv2 required** with a
  pod-blocking hop limit, matching the launch-template hardening in ADR-0009.

### 4. The system node group stays

Karpenter needs somewhere to run that Karpenter itself does not manage (or it
could delete the node hosting its own controller). The 2-node system group from
ADR-0007 remains that stable base; Karpenter scales **workload** capacity on top.

## Consequences

- The cluster now scales to real workloads and, when idle, consolidates back
  toward just the system group, holding the "functional and cheap" line.
- **Teardown ordering gains a step.** Karpenter-provisioned nodes are **not**
  Terraform-managed, so destroying the `eks` stack while they exist orphans EC2
  instances. Teardown must delete the `NodePool` (let Karpenter drain its nodes)
  before the `eks` destroy. Captured in the teardown runbook and
  [layer2-issues.md](../layer2-issues.md).
- First proof that the ADR-0010 GitOps loop delivers a non-trivial component:
  merge a manifest, ArgoCD reconciles, capacity appears. Later components
  (Cilium, observability, Kyverno) follow the same path.
- Karpenter's controller policy is broad by nature (it launches and terminates
  instances). It is scoped where the upstream policy allows (region conditions,
  `PassRole` limited to the node role) and is a deliberate, reviewed grant.
- Deferred: GPU/accelerator `NodePools` for the AI layer, and per-team
  `NodePools` with taints, both land when their workloads do.
