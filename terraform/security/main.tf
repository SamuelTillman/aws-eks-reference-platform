# -----------------------------------------------------------------------------
# Security stack data + locals
#
# Runs as management (registers delegated admins); assumes into security to
# configure the services org-wide. Account IDs from org remote state.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "org/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  account_ids         = data.terraform_remote_state.org.outputs.account_ids
  security_account_id = local.account_ids["security"]
}
