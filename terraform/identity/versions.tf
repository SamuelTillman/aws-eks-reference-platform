terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config: the account-specific `bucket` is supplied at init
  # time from a gitignored backend.hcl (see backend.hcl.example). Initialize:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "identity/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Identity Center (SSO) is administered from the management account in the home
# region, so the default provider is all this stack needs, no cross-account
# assume-role aliases here (see ADR-0004 for stacks that do).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Layer     = "1-identity"
    }
  }
}
