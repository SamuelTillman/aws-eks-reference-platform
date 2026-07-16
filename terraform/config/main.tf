# -----------------------------------------------------------------------------
# Config stack data + locals
#
# Runs as management; assumes into each member account to stand up a recorder.
# Account IDs from org remote state.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "this" {}

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
  mgmt_account_id     = data.aws_caller_identity.current.account_id
  org_id              = data.aws_organizations_organization.this.id

  config_bucket_name = "${var.name_prefix}-config-${local.security_account_id}"

  # Every account that delivers Config to the central bucket.
  all_account_ids = concat(
    [for k, v in local.account_ids : v],
    [local.mgmt_account_id],
  )
}
