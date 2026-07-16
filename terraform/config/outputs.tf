output "config_bucket_name" {
  description = "Central AWS Config delivery bucket (security account)"
  value       = aws_s3_bucket.config.id
}

output "aggregator_name" {
  description = "Organization Config aggregator"
  value       = aws_config_configuration_aggregator.org.name
}

output "recorder_accounts" {
  description = "Accounts with a Config recorder"
  value       = concat(keys(local.account_ids), ["management"])
}
