terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # After first apply, uncomment and run `terraform init -migrate-state`.
  # S3 native locking (use_lockfile): no DynamoDB table needed on TF >= 1.10.
  #
  # backend "s3" {
  #   bucket       = "refplatform-tf-state-<MGMT_ACCOUNT_ID>"
  #   key          = "bootstrap/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
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
