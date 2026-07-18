output "namespace" {
  description = "Namespace ArgoCD runs in"
  value       = var.namespace
}

output "port_forward_command" {
  description = "Open the ArgoCD UI locally (assume workloads-dev first, see docs/layer2-issues.md #4)"
  value       = "kubectl -n ${var.namespace} port-forward svc/argocd-server 8080:80  # then http://localhost:8080"
}

output "initial_admin_password_command" {
  description = "Read the auto-generated initial admin password (rotate/disable after first login)"
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
