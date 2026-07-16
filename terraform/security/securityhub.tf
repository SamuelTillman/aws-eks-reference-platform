# -----------------------------------------------------------------------------
# Security Hub: aggregated findings + standards (FSBP, CIS), administered from
# the security account. Note: Security Hub controls run on AWS Config.
# -----------------------------------------------------------------------------

# Management designates security as the Security Hub delegated administrator.
resource "aws_securityhub_organization_admin_account" "this" {
  count            = var.enable_securityhub ? 1 : 0
  admin_account_id = local.security_account_id
}

# Enable Security Hub in the delegated-admin (security) account. Default
# standards are disabled so we manage standards explicitly below (a fresh build
# never auto-subscribes the legacy CIS 1.2.0). enable_default_standards is a
# create-only, ForceNew argument, so ignore_changes keeps it from destructively
# replacing an account that was first created with the default on (the stray
# CIS 1.2.0 was disabled out-of-band). See ADR-0004 / layer1-plan.
resource "aws_securityhub_account" "security" {
  count    = var.enable_securityhub ? 1 : 0
  provider = aws.security

  enable_default_standards = false

  lifecycle {
    ignore_changes = [enable_default_standards]
  }
}

# Auto-enable Security Hub + default standards for member accounts.
resource "aws_securityhub_organization_configuration" "this" {
  count    = var.enable_securityhub ? 1 : 0
  provider = aws.security

  auto_enable           = true
  auto_enable_standards = "DEFAULT"

  depends_on = [
    aws_securityhub_organization_admin_account.this,
    aws_securityhub_account.security,
  ]
}

# Standards subscriptions in the admin account.
resource "aws_securityhub_standards_subscription" "fsbp" {
  count    = var.enable_securityhub ? 1 : 0
  provider = aws.security

  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.security]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count    = var.enable_securityhub ? 1 : 0
  provider = aws.security

  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.security]
}
