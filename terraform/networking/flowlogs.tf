# -----------------------------------------------------------------------------
# Central VPC flow-logs archive (ADR-0006 §Observability).
#
# A DEDICATED bucket + KMS key in the `security` account, deliberately NOT the
# CloudTrail audit bucket. This keeps the audit trail write-isolated from the
# workload accounts (ADR-0004 §5) while still centralizing flow logs in security
# and extending the audit backbone. Each VPC's flow log (created in its own
# account by the vpc module) delivers here via the log-delivery service.
#
# The whole archive is gated on var.enable_flow_logs so the feature stands down
# to zero (cost discipline).
# -----------------------------------------------------------------------------

locals {
  security_account_id = local.account_ids["security"]
  create_flow_logs    = var.enable_flow_logs ? 1 : 0

  # Accounts whose VPCs deliver flow logs here (scopes the bucket/KMS grants).
  flow_log_source_accounts = [
    local.account_ids["shared_services"],
    local.account_ids["workloads_dev"],
    local.account_ids["workloads_prod"],
  ]
}

# --- KMS key (security account) ---------------------------------------------

data "aws_iam_policy_document" "flow_logs_kms" {
  count = local.create_flow_logs

  statement {
    sid       = "SecurityAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.security_account_id}:root"]
    }
  }

  # The log-delivery service encrypts flow-log objects with this key, only for
  # deliveries originating in our network accounts.
  statement {
    sid       = "AllowFlowLogsDelivery"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.flow_log_source_accounts
    }
  }
}

resource "aws_kms_key" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  description             = "Encryption for ${var.name_prefix} VPC flow logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.flow_logs_kms[0].json
}

resource "aws_kms_alias" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  name          = "alias/${var.name_prefix}-vpc-flow-logs"
  target_key_id = aws_kms_key.flow_logs[0].key_id
}

# --- Bucket (security account) ----------------------------------------------

resource "aws_s3_bucket" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  bucket        = "${var.name_prefix}-vpc-flow-logs-${local.security_account_id}"
  force_destroy = var.force_destroy_flow_logs
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flow_logs[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Flow logs are voluminous and reconstructable, expire them to cap storage cost.
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    id     = "expire-flow-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.flow_log_retention_days
    }
  }
}

data "aws_iam_policy_document" "flow_logs_bucket" {
  count = local.create_flow_logs

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs[0].arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.flow_log_source_accounts
    }
  }

  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.flow_log_source_accounts
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  provider = aws.security
  count    = local.create_flow_logs

  bucket = aws_s3_bucket.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_bucket[0].json
}
