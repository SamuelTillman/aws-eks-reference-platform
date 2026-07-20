# ADR-0015: Dashboard access without a second credential

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Implemented. Closes the last place the platform kept
> a static, shared human credential, and completes the Layer 2 access story.

## Context

Every human path into this platform authenticates through IAM Identity Center
with nothing stored: SSO to the accounts, SSO to the EKS API via access entries
([ADR-0007](0007-eks-cluster-foundation.md)), and OIDC for CI
([ADR-0005](0005-cicd-foundation.md)). Permission boundaries cap all of it
([ADR-0012](0012-permission-boundaries.md)).

Two things did not follow that rule: **ArgoCD** and **Grafana** each shipped with
a built-in local admin account (ArgoCD's generated `admin` password in
`argocd-initial-admin-secret`; Grafana's chart-default password). Both sat behind
a `kubectl port-forward`, so they were never internet-exposed, but they were still
a **second, static, shared credential** in a platform whose headline claim is that
none exist.

### The reframe that matters

The obvious fix looks like "add an ingress and wire SSO." That is the expensive
answer, and it misreads the problem:

- The **network path is already SSO-gated**. `kubectl port-forward` authenticates
  Identity Center -> EKS access entry -> API server authorization. There is no
  stored credential and no internet exposure in that path. Adding a public ingress
  would *reduce* that posture, not improve it.
- The actual defect is narrower: a **second identity system** (app-local
  passwords) layered behind an already-authenticated tunnel.
- Wiring real SSO to these apps also needs a stable **HTTPS callback URL**, which
  needs an ingress and DNS. So "SSO for the dashboards" drags in an ALB (~$16-20/mo
  each), a way to reach a private ALB (VPN or peering, neither of which exists
  here), and certificate management, all to authenticate two admin dashboards.

The cheaper and stronger move is to **delete the second credential** and lean on
the Kubernetes identity that is already Identity Center-backed.

## Decision

Remove the local admin accounts. Reach both dashboards through the existing
SSO-gated Kubernetes path.

### 1. ArgoCD: no admin account, kubeconfig-backed access

Set `admin.enabled: "false"` in `argocd-cm`. There is then no ArgoCD password to
generate, store, rotate, or leak, and no `argocd-initial-admin-secret`.

Operators use ArgoCD's **core mode**, which talks directly to the Kubernetes API
using the caller's kubeconfig:

```sh
argocd admin dashboard -n argocd   # local UI, authenticated as your SSO identity
argocd app list --core             # CLI, same identity
```

Authorization becomes Kubernetes RBAC on the ArgoCD CRDs plus the EKS access
entry, i.e. the same Identity Center identity that governs everything else. One
identity system instead of two. The in-cluster `argocd-server` UI has no login
path by design; that is the point, not a regression.

### 2. Grafana: no login form, anonymous read-only

Disable the login form and grant anonymous **Viewer**:

```yaml
auth: { disable_login_form: true }
auth.anonymous: { enabled: true, org_role: Viewer }
users: { allow_sign_up: false }
```

For read-only dashboards on an ephemeral cluster behind an SSO-gated tunnel, this
is a better posture than a shared admin password: there is no credential to
distribute, and the only way to reach the ClusterIP Service is to already be an
authenticated operator. Nobody can change anything through the UI.

### 3. No ingress, deliberately

The Services stay `ClusterIP`. An ingress arrives when a **workload** needs one,
not to expose two admin dashboards. That keeps the private-first posture and the
near-zero idle cost ([ADR-0008](0008-cicd-lifecycle-teardown-rebuild.md)).

## Consequences

- The platform's zero-stored-credential claim is now true end to end for humans:
  no shared password exists anywhere in the cluster.
- Access is unchanged in convenience (still a port-forward or the local
  dashboard) and strictly better in security (one identity system, SSO-governed).
- **Residual, stated plainly:** Grafana's chart still provisions an admin user
  that its HTTP API would accept over basic auth. The login form is off, the
  Service is ClusterIP, and reaching it requires an SSO-gated tunnel, so the
  practical exposure is small, but it is not zero. Eliminating it properly needs a
  secret store (External Secrets + Secrets Manager) or Amazon Managed Grafana
  (native Identity Center), both deferred.
- If a real ingress arrives later, wiring genuine SSO becomes easy and is the
  natural upgrade: ArgoCD via Dex's SAML connector to Identity Center (with
  Identity Center **groups mapped to ArgoCD RBAC roles**), Grafana via an OIDC
  broker, since Identity Center speaks SAML for custom apps and Grafana OSS only
  does OIDC.
