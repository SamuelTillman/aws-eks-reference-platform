variable "aws_region" {
  description = "Home region for the platform (where Identity Center is enabled)"
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

variable "platform_admin_usernames" {
  description = "Identity Center usernames to add to the platform-admins group (e.g. your SSO admin). Empty = manage membership by hand."
  type        = list(string)
  default     = []
}
