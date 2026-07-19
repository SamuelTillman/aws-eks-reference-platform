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

variable "enable_conformance_pack" {
  description = "Deploy the org-wide baseline conformance pack of managed Config rules (ADR-0009). Bills per rule evaluation; set false to stand it down to zero."
  type        = bool
  default     = true
}

variable "force_destroy_config_bucket" {
  description = "Allow the Config bucket to be destroyed with objects present. Default false: audit/compliance data should not be casually deletable (ADR-0009). Set true only for a deliberate full teardown."
  type        = bool
  default     = false
}
