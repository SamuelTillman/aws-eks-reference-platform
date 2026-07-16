output "log_bucket_name" {
  description = "Central CloudTrail log bucket (security account)"
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "Central CloudTrail log bucket ARN"
  value       = aws_s3_bucket.logs.arn
}

output "kms_key_arn" {
  description = "KMS key encrypting the CloudTrail logs"
  value       = aws_kms_key.cloudtrail.arn
}

output "trail_arn" {
  description = "Organization CloudTrail ARN"
  value       = aws_cloudtrail.org.arn
}
