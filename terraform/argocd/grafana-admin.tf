# -----------------------------------------------------------------------------
# Monitoring namespace (ADR-0016).
#
# The Grafana admin credential is NO LONGER created here. ADR-0015 shipped a
# stopgap (a Terraform `random_password` in a Kubernetes Secret); that has been
# replaced by the secrets pipeline: the value lives in AWS Secrets Manager
# (terraform/eks/external-secrets.tf) and External Secrets materializes the
# `grafana-admin` Secret into this namespace (gitops/external-secrets/).
#
# The namespace itself is still created here, and deliberately: an ExternalSecret
# is namespaced, so `monitoring` must exist before ArgoCD applies it. ArgoCD's
# observability Application also sets CreateNamespace=true, which is then a no-op.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  # ArgoCD adds its own tracking labels once it adopts the namespace.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}
