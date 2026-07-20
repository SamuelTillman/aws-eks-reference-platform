# -----------------------------------------------------------------------------
# ArgoCD itself, via the community argo-helm chart (ADR-0010).
#
# Minimal, private-first: the server is a ClusterIP reached by `kubectl
# port-forward` (no ingress yet). `server.insecure=true` terminates TLS
# at port-forward; a proper LB/ingress with real TLS arrives in a later
# increment. Runs on the existing system node group (no new nodes).
#
# No local admin account (ADR-0015): there is no ArgoCD password to store,
# rotate, or leak. Operators use `argocd admin dashboard` / `argocd --core`,
# which authenticate with the kubeconfig, i.e. Identity Center -> EKS access
# entry. One identity system, zero stored credentials.
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Keep the install lean; harden (HA, resources) in later increments.
  values = [yamlencode({
    configs = {
      params = {
        # UI/API served over HTTP behind port-forward; no in-cluster TLS yet.
        "server.insecure" = true
      }
      cm = {
        # Disable the built-in admin user. With no SSO wired (a stable HTTPS
        # callback URL needs an ingress), the in-cluster UI has no login path by
        # design; access goes through the kubeconfig-backed local dashboard.
        "admin.enabled" = "false"
      }
    }
    server = {
      service = { type = "ClusterIP" }
    }
    # Single-replica controllers are fine for a dev cluster.
    controller = { replicas = 1 }
    repoServer = { replicas = 1 }
  })]
}
