# -----------------------------------------------------------------------------
# Organization CloudTrail → central, KMS-encrypted log archive in `security`.
#
# The trail is created in the management account (org trails must originate
# there) and captures management + all member accounts. The bucket and KMS key
# live in the security account so a workload-account compromise can't tamper
# with the audit trail (ADR-0004 §5).
# -----------------------------------------------------------------------------

# --- KMS key (security account) ---------------------------------------------

data "aws_iam_policy_document" "cloudtrail_kms" {
  # Security account owns/administers the key.
  statement {
    sid       = "EnableSecurityAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.security_account_id}:root"]
    }
  }

  # CloudTrail encrypts log files with this key. Scoped to trails in the
  # management account via the encryption context.
  statement {
    sid       = "AllowCloudTrailEncrypt"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.mgmt_account_id}:trail/*"]
    }
  }

  statement {
    sid       = "AllowCloudTrailDescribeKey"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "cloudtrail" {
  provider = aws.security

  description             = "Encryption for ${var.name_prefix} organization CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.cloudtrail_kms.json
}

resource "aws_kms_alias" "cloudtrail" {
  provider = aws.security

  name          = "alias/${var.name_prefix}-org-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# --- Central log bucket (security account) ----------------------------------

resource "aws_s3_bucket" "logs" {
  provider = aws.security

  bucket        = local.log_bucket_name
  force_destroy = var.force_destroy_logs
}

resource "aws_s3_bucket_versioning" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  provider = aws.security

  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "log_bucket" {
  # Enforce TLS in transit (ADR-0009).
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Object Lock is GOVERNANCE mode (ADR-0017), which by itself any admin holding
  # s3:* could bypass. Deny the bypass (and version deletion) for everyone except
  # the OrganizationAccountAccessRole, so GOVERNANCE behaves like COMPLIANCE for
  # every normal principal while keeping one deliberate, audited break-glass path.
  # Same exemption pattern as the deny-disable-audit SCP.
  dynamic "statement" {
    for_each = var.enable_log_object_lock ? [1] : []
    content {
      sid    = "DenyObjectLockBypassExceptBreakGlass"
      effect = "Deny"
      actions = [
        "s3:BypassGovernanceRetention",
        "s3:DeleteObjectVersion",
        "s3:PutObjectRetention",
      ]
      resources = ["${aws_s3_bucket.logs.arn}/*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "ArnNotLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
      }
    }
  }

  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    # Org trails write under the org ID path; management's own logs under its
    # account ID. Cover both.
    resources = [
      "${aws_s3_bucket.logs.arn}/AWSLogs/${local.org_id}/*",
      "${aws_s3_bucket.logs.arn}/AWSLogs/${local.mgmt_account_id}/*",
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  provider = aws.security

  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.log_bucket.json
}

# --- The organization trail (management account) ----------------------------

resource "aws_cloudtrail" "org" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.logs.id
  kms_key_id     = aws_kms_key.cloudtrail.arn

  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Management events are always captured (the free copy). Data events are
  # opt-in (var.enable_data_events) because of volume/cost.
  dynamic "event_selector" {
    for_each = var.enable_data_events ? [1] : []
    content {
      read_write_type           = "All"
      include_management_events = true

      data_resource {
        type   = "AWS::S3::Object"
        values = ["arn:aws:s3"]
      }
    }
  }

  # The bucket policy and KMS key must exist before the trail validates them.
  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_kms_key.cloudtrail,
  ]
}
