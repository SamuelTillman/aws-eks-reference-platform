output "guardduty_detector_id" {
  description = "GuardDuty detector ID in the security (delegated admin) account"
  value       = try(aws_guardduty_detector.this[0].id, null)
}

output "securityhub_admin_account_id" {
  description = "Security Hub delegated administrator account"
  value       = try(aws_securityhub_organization_admin_account.this[0].admin_account_id, null)
}

output "access_analyzer_arn" {
  description = "Organization IAM Access Analyzer ARN"
  value       = try(aws_accessanalyzer_analyzer.org[0].arn, null)
}
