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

# Immutable numeric IDs of the GitHub owner/repo. Public values (not AWS account
# IDs), from the OIDC token's `repository_owner_id`/`repository_id` claims, or
# `gh api repos/OWNER/REPO --jq '{owner: .owner.id, repo: .id}'`. Set BOTH only
# if your account emits immutable-ID OIDC subjects (`repo:OWNER@<id>/REPO@<id>`);
# leave empty for the plain `repo:OWNER/REPO` subject. See docs/layer2-issues.md #2.
variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub owner (empty = plain OIDC subject)"
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Immutable numeric ID of the GitHub repo (empty = plain OIDC subject)"
  type        = string
  default     = ""
}
