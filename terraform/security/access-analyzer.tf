# -----------------------------------------------------------------------------
# IAM Access Analyzer: an organization-scoped analyzer in the security account,
# surfacing resources shared outside the org.
# -----------------------------------------------------------------------------

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  count             = var.enable_access_analyzer ? 1 : 0
  account_id        = local.security_account_id
  service_principal = "access-analyzer.amazonaws.com"
}

# An ORGANIZATION analyzer created by the delegated admin requires the Access
# Analyzer service-linked role to exist in the MANAGEMENT account. Trusted-access
# enablement creates it only in the delegated-admin account, so manage the
# management-account SLR explicitly (default provider = management).
resource "aws_iam_service_linked_role" "access_analyzer" {
  count            = var.enable_access_analyzer ? 1 : 0
  aws_service_name = "access-analyzer.amazonaws.com"
}

# IAM is eventually consistent: the freshly created SLR isn't immediately
# visible to the Access Analyzer service, so creating the analyzer right away
# fails. Wait for propagation before creating the analyzer.
resource "time_sleep" "access_analyzer_slr" {
  count           = var.enable_access_analyzer ? 1 : 0
  depends_on      = [aws_iam_service_linked_role.access_analyzer]
  create_duration = "30s"
}

resource "aws_accessanalyzer_analyzer" "org" {
  count    = var.enable_access_analyzer ? 1 : 0
  provider = aws.security

  analyzer_name = "${var.name_prefix}-org-analyzer"
  type          = "ORGANIZATION"

  depends_on = [
    aws_organizations_delegated_administrator.access_analyzer,
    time_sleep.access_analyzer_slr,
  ]
}
