# ADR-0007: EKS cluster foundation

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Not built yet. This ADR scopes the **first Layer 2
> increment**, a single working EKS cluster in `workloads-dev` that later
> increments (Cilium, GitOps, observability, policy, Backstage) build on. Each of
> those is its own ADR/increment; this one deliberately stops at "a cluster you
> can deploy to."

## Context

Layer 1 left the workload VPCs ready for Kubernetes: private subnets sized for pod
density and pre-tagged for discovery ([ADR-0006](0006-network-architecture.md)),
centralized egress, private ECR pulls a flag away, and cross-account deploy roles
([ADR-0005](0005-cicd-foundation.md)). Layer 2's full scope is a whole platform
(Cilium, mesh, Prometheus/OTel, ArgoCD, Kyverno, Backstage), too big for one
reviewable change. This ADR fixes the **cluster foundation** and the patterns the
rest inherits; the platform add-ons come as GitOps increments once ArgoCD exists.

## Decision

A single **`refplatform-dev`** EKS cluster in the `workloads-dev` account, in the
private subnets of the dev VPC, deployed by a new `terraform/eks` stack (state key
`eks/terraform.tfstate`) that assumes into `workloads-dev` via a provider alias and
reads subnet/account IDs from `networking` + `org` remote state. **Account IDs are
never hardcoded.**

### Scoping decisions (flagged, veto any before we write Terraform)

| # | Decision | Choice | Why this default |
|---|---|---|---|
| 1 | **Environments** | **dev only**, this increment | Fast, low-blast-radius foundation; prod is a later increment behind the [ADR-0005](0005-cicd-foundation.md) approval gate. |
| 2 | **Node compute** | **Small managed node group** now (system tier), **Karpenter next increment** for workloads | Karpenter's controller needs a stable place to run; a 2-3 node system MNG provides it. Karpenter (spot + consolidation) then does the real autoscaling and cost story. |
| 3 | **CNI** | **AWS VPC CNI** (prefix delegation on) | Consistent with ADR-0006 subnet sizing ("VPC-CNI assigns pod IPs from the subnet"). Cilium is its own increment; overlay-vs-ENI (which changes the IPAM assumption) gets decided there. |
| 4 | **API endpoint** | **Private enabled + public enabled, CIDR-restricted** to an admin allowlist var | Lets you and CI reach the API while iterating without standing up a bastion, without exposing it to the world. Prod goes **fully private** (SSM access). |

### Cluster specifics

- **Auth mode:** EKS **access entries** (API mode), not the legacy `aws-auth`
  ConfigMap. Bootstrap maps the admin SSO role and the CI/CD deploy role.
- **Workload IAM:** **EKS Pod Identity** as the default (simpler than IRSA/OIDC);
  IRSA remains available for add-ons that still require it.
- **Managed add-ons (Terraform):** VPC CNI, CoreDNS, kube-proxy, EKS Pod Identity
  Agent. Everything above this line (mesh, observability, Kyverno, Backstage) is
  delivered by **ArgoCD** in later increments, not Terraform.
- **Secrets encryption:** envelope encryption with a dedicated KMS key; node EBS
  volumes encrypted.
- **Control-plane logging:** api/audit/authenticator/controllerManager/scheduler
  logs → CloudWatch, behind `enable_control_plane_logs` (cost-aware, default on
  for a security-reference platform).
- **Version:** pin a specific EKS minor (latest stable at build time); upgrades
  are deliberate, plan-reviewed changes.

### EKS-readiness reuse

Subnets already carry `kubernetes.io/role/internal-elb`, `.../elb`, and
`kubernetes.io/cluster/refplatform-dev=shared` from ADR-0006, the cluster and
load balancers discover them with no retagging.

### Cost posture

First standing hourly cost in the platform: control plane **$0.10/hr**, plus the
system node group (small; spot-eligible). Fully `terraform destroy`-able between
sessions like every other stack; control-plane logs and node count are the tunable
knobs.

## Consequences

- A real, deployable dev cluster lands in one reviewable increment; the platform
  add-ons layer on via GitOps without reopening this stack.
- Choosing VPC CNI now means the **Cilium increment must decide ENI vs overlay**
  mode explicitly, overlay would break ADR-0006's "pods get VPC IPs" assumption
  and the subnet sizing rationale. Flagged there.
- Access entries + Pod Identity commit to the **modern** EKS auth/IAM path; anyone
  forking from older EKS habits (aws-auth, IRSA-everywhere) will see the newer
  pattern instead.
- Public-but-restricted endpoint is a pragmatic iteration choice, not the end
  state, prod's fully-private endpoint is the reference posture.
- Standing cost begins here. The platform is still stand-down-able, but "near-zero
  when idle" now means **destroying** the cluster, not just toggling a flag.
- Deferred to their own increments/ADRs: Karpenter, Cilium (+ mesh), ArgoCD,
  observability, Kyverno, Backstage, and the prod cluster.
