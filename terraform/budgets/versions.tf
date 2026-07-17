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
    key          = "budgets/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Budgets live in the management (payer) account and cover consolidated org spend.
# Runs as management directly, no assume-role needed.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Layer     = "cost"
    }
  }
}
