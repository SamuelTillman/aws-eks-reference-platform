terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config: the account-specific `bucket` is supplied at init
  # time from a gitignored backend.hcl (see backend.hcl.example), so no account
  # ID lands in version control. Initialize with:
  #   terraform init -backend-config=backend.hcl
  # S3 native locking (use_lockfile): no DynamoDB table needed on TF >= 1.10.
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}
