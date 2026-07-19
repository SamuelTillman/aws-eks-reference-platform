# gitops/

The GitOps source tree for the `refplatform-dev` cluster (ADR-0010). ArgoCD runs
in the cluster and continuously reconciles it to match what is committed here. You
change the cluster by merging a commit, not by running `kubectl apply` by hand.

## How it works (app-of-apps)

- `terraform/argocd` bootstraps ArgoCD and creates one **root Application** that
  points at [`apps/`](apps/).
- Every platform component is added as its own ArgoCD `Application` YAML under
  [`apps/`](apps/). The root app watches this directory (`recurse: true`) and
  adopts anything it finds, so adding a component is just "commit a manifest".
- Child apps sync automatically with self-heal and prune: the cluster always
  matches Git, drift is corrected, and deleting a manifest removes the component.

## Layout

```
gitops/
  README.md        this file
  apps/            one ArgoCD Application per platform component (the root app
                   watches this dir with recurse:true)
    karpenter-oci-repo.yaml   registers the public Karpenter OCI Helm registry
    karpenter.yaml            Karpenter controller Helm chart (sync-wave 0)
    karpenter-nodepool.yaml   Application sourcing the NodePool/EC2NodeClass below
    observability.yaml        kube-prometheus-stack: Prometheus + Grafana (wave 2)
    kyverno.yaml              Kyverno admission policy engine (wave 2)
    kyverno-policies.yaml     Application sourcing the ClusterPolicies below (wave 3)
  karpenter/       raw custom resources applied by karpenter-nodepool.yaml. Kept
                   OUT of apps/ so the root app does not try to apply these CRs
                   before their CRDs exist.
    ec2nodeclass.yaml
    nodepool.yaml
  kyverno/         Kyverno ClusterPolicy CRs applied by kyverno-policies.yaml
                   (also kept out of apps/ for the same CRD-ordering reason).
    disallow-latest-tag.yaml      (Enforce)
    require-requests-limits.yaml  (Audit)
    disallow-privileged.yaml      (Audit)
    require-run-as-nonroot.yaml   (Audit)
```

Components map to ADRs: Karpenter [ADR-0011], observability [ADR-0013], Kyverno
[ADR-0014]. Next up (Cilium, Backstage) follow the same shape.

## Adding a component

Drop an `Application` manifest in `apps/`, for example `apps/karpenter.yaml`,
pointing at that component's chart or manifests. Merge to `main` and ArgoCD picks
it up. Keep each app small and independently syncable.

**Ordering:** if a component installs CRDs that other manifests use, split it, put
the chart in `apps/` at `argocd.argoproj.io/sync-wave: "0"` and the custom
resources in a sibling dir referenced by a second Application at sync-wave `"1"`,
so the CRDs exist first (see Karpenter above).

**CRs vs Applications:** raw Kubernetes manifests that are not `Application`s must
live OUTSIDE `apps/` (the root app recurses `apps/` and would apply them directly).
Put them in their own top-level dir (e.g. `karpenter/`) and point an Application at
it.
