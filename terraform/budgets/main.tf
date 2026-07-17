# -----------------------------------------------------------------------------
# Monthly cost budget with $increment alerts (ADR-0008).
#
# One monthly COST budget covering consolidated org spend, emailing at every
# `budget_increment` dollars of ACTUAL spend up to `budget_ceiling`. Independent
# of Cost Explorer (Budgets does not require it to be enabled).
# -----------------------------------------------------------------------------

locals {
  # Alert thresholds: increment, 2*increment, ... up to and including the ceiling.
  thresholds = range(var.budget_increment, var.budget_ceiling + 1, var.budget_increment)
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_ceiling)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # One ACTUAL-spend notification per threshold. Skipped entirely when no email
  # is configured (e.g. in CI plan), which keeps the budget valid with zero
  # notifications rather than emailing an empty address.
  dynamic "notification" {
    for_each = var.alert_email != "" ? local.thresholds : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}
