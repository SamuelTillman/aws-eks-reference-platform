# -----------------------------------------------------------------------------
# GuardDuty: threat detection org-wide, administered from the security account.
# -----------------------------------------------------------------------------

# Management designates security as the GuardDuty delegated administrator.
resource "aws_guardduty_organization_admin_account" "this" {
  count            = var.enable_guardduty ? 1 : 0
  admin_account_id = local.security_account_id
}

# Detector in the delegated-admin (security) account.
resource "aws_guardduty_detector" "this" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.security
  enable   = true
}

# Auto-enable GuardDuty for all current and future member accounts.
resource "aws_guardduty_organization_configuration" "this" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.security

  detector_id                      = aws_guardduty_detector.this[0].id
  auto_enable_organization_members = "ALL"

  depends_on = [aws_guardduty_organization_admin_account.this]
}
