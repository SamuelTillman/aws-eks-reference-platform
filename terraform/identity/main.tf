# -----------------------------------------------------------------------------
# Identity stack data sources
#
# Reads the live Identity Center instance and the org stack's remote state
# (for member account IDs, so none are hardcoded, see ADR-0004 §2).
# -----------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}

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
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # Member account IDs come from org remote state; the management account ID
  # comes from the caller (this stack runs as management).
  account_ids = merge(
    data.terraform_remote_state.org.outputs.account_ids,
    { management = data.aws_caller_identity.current.account_id },
  )
}
