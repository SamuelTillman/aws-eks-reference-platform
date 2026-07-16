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

variable "azs" {
  description = "Availability zones for subnet spread (3 for HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
