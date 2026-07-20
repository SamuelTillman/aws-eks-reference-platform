# -----------------------------------------------------------------------------
# S3 Object Lock on the audit-log bucket (ADR-0017), the WORM control that makes
# the CloudTrail archive tamper-evident AND tamper-resistant. SCPs stop the API
# calls that disable logging; Object Lock stops deletion of the log DATA itself.
#
# IRREVERSIBLE: Object Lock cannot be disabled once enabled on a bucket. It is
# applied here as a separate configuration resource (NOT the bucket's create-time
# `object_lock_enabled` argument) precisely so Terraform does not have to replace
# the bucket, which would destroy the archive it exists to protect. Enabling in
# place requires versioning, which is already on.
#
# Scope note: Object Lock applies to objects written AFTER enablement. Objects
# already in the bucket keep no retention unless set explicitly.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_object_lock_configuration" "logs" {
  count    = var.enable_log_object_lock ? 1 : 0
  provider = aws.security

  bucket = aws_s3_bucket.logs.id

  rule {
    default_retention {
      mode = var.log_object_lock_mode
      days = var.log_object_lock_days
    }
  }

  # Versioning is a hard prerequisite for Object Lock.
  depends_on = [aws_s3_bucket_versioning.logs]
}
