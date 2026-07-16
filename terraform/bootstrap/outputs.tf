output "state_bucket" {
  description = "S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.tf_state.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC. Set it as the AWS_ROLE_ARN repo variable"
  value       = aws_iam_role.github_actions.arn
}
