# -----------------------------------------------------------------------------
# Bootstrap: Terraform state backend
#
# First run uses local state (see docs/bootstrap.md step 6), then migrates
# into the bucket created here with `terraform init -migrate-state`.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.name_prefix}-tf-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 native state locking (Terraform >= 1.10) uses conditional writes,
# so a DynamoDB lock table isn't required anymore. See the backend config
# comment in versions.tf.

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project   = var.name_prefix
    ManagedBy = "terraform"
    Layer     = "0-bootstrap"
  }
}
