variable "aws_region" {
  description = "Home region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix/tag value for platform resources"
  type        = string
  default     = "refplatform"
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform remote state (embeds the mgmt account ID; supply via gitignored tfvars)"
  type        = string
}

variable "enable_data_events" {
  description = "Log S3/Lambda data events in CloudTrail. Off by default: data events can be voluminous and costly."
  type        = bool
  default     = false
}

variable "force_destroy_logs" {
  description = "Allow the audit-log bucket to be destroyed with objects present. Default false: the audit trail should not be casually deletable, and this is the safety prerequisite for S3 Object Lock (ADR-0009). Set true only for a deliberate full teardown."
  type        = bool
  default     = false
}
