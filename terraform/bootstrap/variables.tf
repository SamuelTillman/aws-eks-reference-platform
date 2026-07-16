variable "name_prefix" {
  description = "Prefix for all bootstrap resources (e.g. 'refplatform')"
  type        = string
  default     = "refplatform"
}

variable "aws_region" {
  description = "Home region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub org or username that owns this repository"
  type        = string
}

variable "github_repo" {
  description = "Repository name trusted for OIDC role assumption"
  type        = string
  default     = "aws-eks-reference-platform"
}
