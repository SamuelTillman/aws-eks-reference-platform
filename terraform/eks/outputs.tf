output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_certificate_authority" {
  description = "Base64 CA data for kubeconfig"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "node_role_arn" {
  description = "System node group IAM role ARN"
  value       = aws_iam_role.node.arn
}

# kubectl access (run in workloads-dev): fill in the account ID from your SSO.
output "kubeconfig_command" {
  description = "Command to write kubeconfig for this cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}
