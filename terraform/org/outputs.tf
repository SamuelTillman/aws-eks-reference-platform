output "account_ids" {
  description = "Member account IDs by name"
  value = {
    security        = aws_organizations_account.security.id
    shared_services = aws_organizations_account.shared_services.id
    workloads_dev   = aws_organizations_account.workloads_dev.id
    workloads_prod  = aws_organizations_account.workloads_prod.id
  }
}

output "ou_ids" {
  description = "Organizational unit IDs"
  value = {
    security       = aws_organizations_organizational_unit.security.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    workloads      = aws_organizations_organizational_unit.workloads.id
  }
}
