# Teardown and rebuild

How to stand the platform down to near-zero cost and bring it back, entirely from
the GitHub Actions button ([ADR-0008](adr/0008-cicd-lifecycle-teardown-rebuild.md)).

The button is the **Platform Lifecycle** workflow: repo -> Actions -> Platform
Lifecycle (apply / destroy) -> Run workflow, then pick `stack`, `action`, and
(for destroy) type the stack name into `confirm`. Every rebuildable layer is an
individual choice: **networking, eks, argocd, security**. `bootstrap`, `org`,
`identity`, and `logging` are never targets.

## Each stack, individually

- **networking** apply/destroy. Independent (only needs the always-on org state).
- **eks** apply/destroy. Reads networking's state, so networking must exist first.
- **argocd** apply/destroy. Lives inside the cluster (private endpoint), so the
  run **temporarily adds the runner's IP** to the endpoint allowlist, does the
  work, then removes it (an always-run step, even on failure). Needs the cluster
  up for apply; on destroy after the cluster is gone it just clears state.
- **security** stand down (`destroy`) / restore (`apply`) the paid detectors.

Order is the only constraint, and it is just dependency physics:
`networking -> eks -> argocd`.

A rebuild reproduces the *optimized* cluster (EKS 1.35, spot, single NAT, endpoint
restricted to your IP) because the workflow feeds this environment's profile:
non-sensitive settings inline, sensitive ones from secrets
`EKS_PUBLIC_ACCESS_CIDRS` and `EKS_ADMIN_PRINCIPAL_ARNS`.

> **If your egress IP changed**, update the `EKS_PUBLIC_ACCESS_CIDRS` secret
> (repo -> Settings -> Secrets) to `["<new-ip>/32"]` before the eks rebuild, or
> you will not be able to reach the API endpoint afterward.

## Teardown (to near-zero)

Run these from the button, in order:

0. **If Karpenter has provisioned any nodes** ([ADR-0011](adr/0011-karpenter-autoscaling.md)):
   delete the NodePool first so Karpenter drains and terminates its own nodes
   before the cluster goes away, those EC2 instances are **not** Terraform-managed,
   so a straight `eks` destroy would orphan them. With kubeconfig set (see below):
   `kubectl delete nodepool --all && kubectl wait --for=delete nodes -l platform.refplatform/tier=karpenter --timeout=5m`.
   If the cluster is already gone, clean up any leftovers by terminating instances
   tagged `karpenter.sh/nodepool` in `workloads-dev`.
1. `stack=argocd`, `action=destroy`, `confirm=argocd`  (removes ArgoCD)
2. `stack=eks`, `action=destroy`, `confirm=eks`  (~10 min; deletes the cluster)
3. `stack=networking`, `action=destroy`, `confirm=networking`  (~5 min; a guard
   blocks this until the cluster is gone)
4. Optional, for true near-zero: `stack=security`, `action=destroy`,
   `confirm=security` disables GuardDuty/Security Hub (trades away audit coverage
   while idle). AWS Config has no off switch; its idle cost is small.

> Shortcut: you can skip step 1 and go straight to `eks` destroy, the cluster
> deletion takes ArgoCD with it. Then a later `argocd` destroy simply clears the
> stale state (the workflow detects the missing cluster and does `state rm`).

After 1-3 the ~$245/mo of cluster + NAT + Transit Gateway is $0; only the Layer 1
governance (Config, Security Hub unless stood down, CloudTrail, S3) remains,
roughly $15-40/mo.

## Rebuild

From the button, in order:

1. If you stood down security: `stack=security`, `action=apply`.
2. `stack=networking`, `action=apply`  (~5 min; single NAT)
3. `stack=eks`, `action=apply`  (~15 min; EKS 1.35, spot, endpoint restricted to
   your IP, your admin roles mapped)
4. `stack=argocd`, `action=apply`  (adds the runner IP, installs ArgoCD, removes
   the IP)

First refresh SSO if you also want to `kubectl` locally, and update
`EKS_PUBLIC_ACCESS_CIDRS` if your IP changed.

### Reaching the cluster afterward

See [layer2-issues.md](layer2-issues.md) #4. In short: assume the workloads-dev
`OrganizationAccountAccessRole`, export the temporary creds, then
`aws eks update-kubeconfig --name refplatform-dev --region us-east-1` (without
`--role-arn`) and `kubectl get nodes`.

### Reaching the dashboards (no passwords, ADR-0015)

Neither dashboard has a local admin account; both ride your SSO identity.

- **ArgoCD:** `argocd admin dashboard -n argocd`, a local UI authenticated by your
  kubeconfig (Identity Center -> EKS access entry). CLI equivalent:
  `argocd app list --core`. The in-cluster UI has no login path by design.
- **Grafana:** `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`
  then **http://localhost:3000** (plain http). No login: anonymous read-only
  Viewer, so there is nothing to type and nothing to leak.
