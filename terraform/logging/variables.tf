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

# --- S3 Object Lock (ADR-0017) ----------------------------------------------

variable "enable_log_object_lock" {
  description = "Enable S3 Object Lock (WORM) on the audit-log bucket. IRREVERSIBLE: Object Lock cannot be turned off once enabled on a bucket."
  type        = bool
  default     = true
}

variable "log_object_lock_mode" {
  description = "Object Lock retention mode. GOVERNANCE (default) blocks deletion for anyone without s3:BypassGovernanceRetention, which the bucket policy denies, leaving a deliberate break-glass path. COMPLIANCE is absolute: not even root can delete before expiry, and it cannot be shortened. Use COMPLIANCE only when a regulator requires it."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.log_object_lock_mode)
    error_message = "log_object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "log_object_lock_days" {
  description = "Default retention in days applied to every new audit object. Deliberately short for a reference platform (locked objects cannot be deleted for this long); a real audit trail would use 365+."
  type        = number
  default     = 7

  validation {
    condition     = var.log_object_lock_days > 0
    error_message = "log_object_lock_days must be greater than 0."
  }
}
