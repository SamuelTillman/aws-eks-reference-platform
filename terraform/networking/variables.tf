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

variable "enable_flow_logs" {
  description = "Deliver VPC flow logs from every VPC to the central archive in the security account (ADR-0006). Small per-GB delivery + storage cost, bounded by flow_log_retention_days."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to retain flow-log objects before lifecycle expiry"
  type        = number
  default     = 90
}

variable "force_destroy_flow_logs" {
  description = "Allow the flow-logs bucket to be destroyed with objects present (keeps the platform destroyable/rebuildable)"
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create ECR/STS/CloudWatch Logs interface endpoints in the workload VPCs (ADR-0006). Off by default, flat hourly per-AZ cost; needed once EKS nodes run in Layer 2."
  type        = bool
  default     = false
}
