terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Partial backend config (see backend.hcl.example). Initialize with:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "security/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Default provider: management account (registers delegated administrators).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Layer     = "1-security"
    }
  }
}

# security account = delegated administrator for the org security services.
# Reached by assuming its OrganizationAccountAccessRole (ADR-0004 §2/§3);
# account ID comes from the org stack's remote state.
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
      Layer     = "1-security"
    }
  }
}
