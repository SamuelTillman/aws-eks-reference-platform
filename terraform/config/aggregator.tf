# -----------------------------------------------------------------------------
# Organization Config aggregator in the security account: a single pane of
# resource configuration across all accounts and regions.
# -----------------------------------------------------------------------------

# Delegate Config multi-account setup to the security account.
resource "aws_organizations_delegated_administrator" "config" {
  account_id        = local.security_account_id
  service_principal = "config-multiaccountsetup.amazonaws.com"
}

# The delegated-admin registration is eventually consistent; the aggregator's
# PutConfigurationAggregator checks it and fails if called too soon. Wait for
# the registration to propagate.
resource "time_sleep" "config_delegated_admin" {
  depends_on      = [aws_organizations_delegated_administrator.config]
  create_duration = "60s"
}

# Role the aggregator uses to enumerate org accounts.
resource "aws_iam_role" "aggregator" {
  provider = aws.security
  name     = "${var.name_prefix}-config-aggregator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  provider   = aws.security
  role       = aws_iam_role.aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security
  name     = "${var.name_prefix}-org"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.aggregator.arn
  }

  depends_on = [
    time_sleep.config_delegated_admin,
    aws_iam_role_policy_attachment.aggregator,
  ]
}
