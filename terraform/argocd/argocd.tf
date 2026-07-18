# -----------------------------------------------------------------------------
# ArgoCD itself, via the community argo-helm chart (ADR-0010).
#
# Minimal, private-first: the server is a ClusterIP reached by `kubectl
# port-forward` for now (no ingress yet). `server.insecure=true` terminates TLS
# at port-forward; a proper LB/ingress with real TLS arrives in a later
# increment. Runs on the existing system node group (no new nodes).
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Keep the install lean; harden (HA, resources, SSO) in later increments.
  values = [yamlencode({
    configs = {
      params = {
        # UI/API served over HTTP behind port-forward; no in-cluster TLS yet.
        "server.insecure" = true
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
