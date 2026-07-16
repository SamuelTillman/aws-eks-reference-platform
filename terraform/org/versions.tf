terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Fill in after bootstrap creates the bucket:
  # backend "s3" {
  #   bucket       = "refplatform-tf-state-<MGMT_ACCOUNT_ID>"
  #   key          = "org/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "refplatform"
      ManagedBy = "terraform"
      Layer     = "0-org"
    }
  }
}
