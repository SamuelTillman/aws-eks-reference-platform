# -----------------------------------------------------------------------------
# CI/CD stack data + locals
#
# Runs as management; assumes into shared-services + workload accounts to create
# OIDC deploy roles and the central registry. Account IDs from org remote state.
# -----------------------------------------------------------------------------

data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "org/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  account_ids = data.terraform_remote_state.org.outputs.account_ids

  # Trust conditions per deployment target.
  sub_main = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  sub_prod = "repo:${var.github_org}/${var.github_repo}:environment:prod"

  deploy_role_name = "${var.name_prefix}-github-actions-deploy"
}
