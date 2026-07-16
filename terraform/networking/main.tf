# -----------------------------------------------------------------------------
# Networking stack data + IPAM plan (ADR-0006)
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

  # IPAM: supernet 10.0.0.0/12, one /16 per account (ADR-0006).
  cidrs = {
    egress = "10.0.0.0/16" # shared-services hub
    dev    = "10.1.0.0/16"
    prod   = "10.2.0.0/16"
  }
}
