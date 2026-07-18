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
  apps/            one ArgoCD Application per platform component (empty until
                   the first component increment: Karpenter, then Cilium,
                   observability, Kyverno, Backstage)
```

## Adding a component

Drop an `Application` manifest in `apps/`, for example `apps/karpenter.yaml`,
pointing at that component's chart or manifests. Merge to `main` and ArgoCD picks
it up. Keep each app small and independently syncable.
