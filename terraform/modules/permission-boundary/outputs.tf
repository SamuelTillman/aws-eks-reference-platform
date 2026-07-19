output "arn" {
  description = "ARN of the permission-boundary policy (set as permissions_boundary on privileged roles)"
  value       = aws_iam_policy.boundary.arn
}

output "name" {
  description = "Name of the permission-boundary policy"
  value       = aws_iam_policy.boundary.name
}
