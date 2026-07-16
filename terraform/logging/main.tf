# -----------------------------------------------------------------------------
# Logging stack data + locals
#
# Runs as management; assumes into the security account for the log archive.
# Account IDs come from the org stack's remote state (ADR-0004 §2).
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

  trail_name      = "${var.name_prefix}-org-trail"
  log_bucket_name = "${var.name_prefix}-org-cloudtrail-${local.security_account_id}"
  trail_arn       = "arn:aws:cloudtrail:${var.aws_region}:${local.mgmt_account_id}:trail/${local.trail_name}"
}
