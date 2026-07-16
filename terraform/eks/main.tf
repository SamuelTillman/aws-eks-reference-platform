# -----------------------------------------------------------------------------
# EKS stack data + locals (ADR-0007).
#
# Reads account IDs from the `org` stack and the dev VPC's private subnets from
# the `networking` stack, nothing hardcoded, no account IDs in tracked files.
# -----------------------------------------------------------------------------

data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "org/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "networking/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  cluster_name = "${var.name_prefix}-dev"

  # EKS nodes and control-plane ENIs land in the dev VPC's private subnets
  # (sized + tagged for this in ADR-0006).
  private_subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids["dev"]
}
