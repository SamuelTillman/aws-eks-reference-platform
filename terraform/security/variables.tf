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

variable "enable_guardduty" {
  description = "Enable GuardDuty org-wide with security as delegated admin"
  type        = bool
  default     = true
}

variable "enable_securityhub" {
  description = "Enable Security Hub org-wide (FSBP + CIS) with security as delegated admin"
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = "Enable an organization-scoped IAM Access Analyzer in security"
  type        = bool
  default     = true
}
