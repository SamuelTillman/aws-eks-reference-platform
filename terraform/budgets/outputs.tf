output "budget_name" {
  description = "Name of the monthly cost budget"
  value       = aws_budgets_budget.monthly.name
}

output "alert_thresholds" {
  description = "Dollar thresholds that trigger an actual-spend alert"
  value       = local.thresholds
}

output "notifications_enabled" {
  description = "Whether email notifications are configured (false when alert_email is empty)"
  value       = var.alert_email != ""
}
