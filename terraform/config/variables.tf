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

variable "force_destroy_config_bucket" {
  description = "Allow the Config bucket to be destroyed with objects present. True keeps the platform destroyable/rebuildable."
  type        = bool
  default     = true
}
