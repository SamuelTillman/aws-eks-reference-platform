variable "aws_region" {
  description = "Home region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "allowed_regions" {
  description = "Regions member accounts may use"
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}

variable "org_access_role_name" {
  description = "Admin role created in each vended account for cross account access"
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "account_emails" {
  description = "Unique root email per member account (plus addressing works: you+aws-dev@yourdomain.com)"
  type = object({
    security        = string
    shared_services = string
    workloads_dev   = string
    workloads_prod  = string
  })
}
