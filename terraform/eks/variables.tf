variable "aws_region" {
  description = "Home region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix/tag value for platform resources (cluster is <name_prefix>-dev)"
  type        = string
  default     = "refplatform"
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform remote state (embeds the mgmt account ID; supply via gitignored tfvars)"
  type        = string
}

variable "cluster_version" {
  description = "EKS control-plane minor version. Pin it; upgrades are deliberate, plan-reviewed changes."
  type        = string
  default     = "1.31"
}

# --- Endpoint access (ADR-0007 decision 4) ----------------------------------

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Private access is always on; keep this tight (your admin egress IP). Empty means no public access."
  type        = list(string)
  default     = []

  # Guard against opening the API server to the world (ADR-0009).
  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs must not include 0.0.0.0/0; that would expose the EKS API server to the entire internet."
  }
}

# --- Access entries (ADR-0007: API auth mode) -------------------------------

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin via EKS access entries (e.g. the admin SSO role, the CI/CD deploy role). The Terraform creator role is admin automatically."
  type        = list(string)
  default     = []
}

# --- System node group ------------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the system managed node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT for the system node group"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired node count (system tier; Karpenter handles workload scale in a later increment)"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Node root EBS volume size (GiB)"
  type        = number
  default     = 50
}

# --- Cost / observability knobs ---------------------------------------------

variable "enable_control_plane_logs" {
  description = "Ship control-plane logs (api/audit/authenticator/controllerManager/scheduler) to CloudWatch. On for a security-reference platform; carries CloudWatch cost."
  type        = bool
  default     = true
}
