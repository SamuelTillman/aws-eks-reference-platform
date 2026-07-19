# -----------------------------------------------------------------------------
# Per-account AWS Config: recorder + delivery channel → central bucket.
# Instantiated once per account with the matching provider alias.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Permission boundary (ADR-0012 phase 3), resolved in this account. Empty name
  # keeps it optional for forks that have not created the boundary yet.
  permission_boundary_arn = var.permission_boundary_name != "" ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permission_boundary_name}" : null
}

resource "aws_iam_role" "config" {
  name                 = "${var.name_prefix}-config-recorder"
  permissions_boundary = local.permission_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.name_prefix}-channel"
  s3_bucket_name = var.bucket_name

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
