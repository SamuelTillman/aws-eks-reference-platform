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

variable "github_org" {
  description = "GitHub org or username that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "Repository trusted for OIDC role assumption"
  type        = string
  default     = "aws-eks-reference-platform"
}

variable "ecr_repositories" {
  description = "ECR repositories to create in shared-services (demo workload services by default)"
  type        = list(string)
  default     = ["charter-api", "charter-frontend", "charter-jobs"]
}

variable "deploy_role_policy_arn" {
  description = "Managed policy attached to each deploy role. Broad for now, secured by tight OIDC trust; narrow per workload in Layer 2 (ADR-0005)."
  type        = string
  default     = "arn:aws:iam::aws:policy/AdministratorAccess"
}
