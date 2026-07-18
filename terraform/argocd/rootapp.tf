# -----------------------------------------------------------------------------
# The one root Application: app-of-apps (ADR-0010).
#
# Created via the argocd-apps chart (Helm applies the Application AFTER ArgoCD's
# CRDs exist, sidestepping the kubernetes_manifest "CRD must exist at plan time"
# problem). It points at gitops/apps in this repo; every platform component
# (Karpenter, Cilium, observability, ...) lands there as its own Application and
# is picked up automatically. This is the only Terraform-managed Application.
# -----------------------------------------------------------------------------

resource "helm_release" "root_app" {
  name      = "root"
  namespace = var.namespace

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = var.namespace
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          path           = var.gitops_path
          targetRevision = var.gitops_revision
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
