# -----------------------------------------------------------------------------
# Grafana admin credential (ADR-0015).
#
# Grafana OSS requires an admin user to exist, it cannot be disabled. What CAN be
# removed is the well-known chart default (`prom-operator`), which is the actual
# risk. A random 32-char password is generated here and delivered as a Kubernetes
# Secret that the Grafana chart consumes via `admin.existingSecret`.
#
# Properties: never in Git, unique per rebuild, never surfaced (no output). It
# does live in Terraform state, which is the encrypted, access-controlled S3
# backend, an accepted trade for this platform. The credential is also inert in
# practice: the login form is disabled and Grafana is anonymous read-only.
#
# Lives in this stack because it is the only one with a Kubernetes provider and it
# runs BEFORE ArgoCD syncs the observability Application, so the Secret exists by
# the time Grafana's pods start. Replacing this with External Secrets +
# Secrets Manager is the planned increment (ADR-0016).
# -----------------------------------------------------------------------------

resource "random_password" "grafana_admin" {
  length = 32
  # Avoid quoting/escaping hazards in env vars and ini files.
  special          = true
  override_special = "-_.~"
}

# ArgoCD's observability Application also sets CreateNamespace=true; creating it
# here first is a no-op for ArgoCD and lets the Secret land before the chart syncs.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  # ArgoCD may add its own tracking labels once it adopts the namespace.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }

  type = "Opaque"
}
