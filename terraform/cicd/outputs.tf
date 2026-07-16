output "deploy_role_arns" {
  description = "GitHub Actions deploy role ARNs by account"
  value = {
    shared_services = module.oidc_shared_services.role_arn
    workloads_dev   = module.oidc_workloads_dev.role_arn
    workloads_prod  = module.oidc_workloads_prod.role_arn
  }
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by name"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
