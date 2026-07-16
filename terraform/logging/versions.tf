terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config (see backend.hcl.example). Initialize with:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "logging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Default provider: the management account (org CloudTrail must originate here).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Layer     = "1-logging"
    }
  }
}

# The security account is the log archive. We reach it by assuming its
# OrganizationAccountAccessRole (ADR-0004 §2). The account ID comes from the org
# stack's remote state, so it's never hardcoded.
provider "aws" {
  alias  = "security"
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["security"]}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Layer     = "1-logging"
    }
  }
}
