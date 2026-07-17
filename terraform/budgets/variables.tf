variable "aws_region" {
  description = "Home region for the platform (AWS Budgets is global; API lives in us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix/tag value for platform resources"
  type        = string
  default     = "refplatform"
}

variable "alert_email" {
  description = "Email address for budget alerts. Set in gitignored tfvars (keeps a personal address out of the public repo). Empty means the budget is created without notifications (used so CI can plan without the address)."
  type        = string
  default     = ""
}

variable "budget_ceiling" {
  description = "Monthly budget limit in USD, and the top of the alert range. Alerts fire at each increment up to this. AWS allows up to 10 notifications per budget, so ceiling/increment must be <= 10 without a quota increase."
  type        = number
  default     = 500
}

variable "budget_increment" {
  description = "Alert at every N dollars of ACTUAL spend (50 => $50, $100, $150, ...)"
  type        = number
  default     = 50
}
