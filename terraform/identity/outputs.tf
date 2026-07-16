output "permission_set_arns" {
  description = "Permission set ARNs by name"
  value       = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.arn }
}

output "group_ids" {
  description = "Identity Center group IDs by name"
  value       = { for k, g in aws_identitystore_group.this : k => g.group_id }
}

output "assignment_keys" {
  description = "group:account assignments created by this stack"
  value       = keys(local.assignments)
}
