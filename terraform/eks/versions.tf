terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial backend config (see backend.hcl.example). Initialize with:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

locals {
  default_tags = {
    Project   = var.name_prefix
    ManagedBy = "terraform"
    Layer     = "2-eks"
  }
}

# Enters as management; reads remote state from the state bucket (mgmt has access).
provider "aws" {
  region = var.aws_region
  default_tags { tags = local.default_tags }
}

# The dev cluster lives in workloads-dev, assume its OrganizationAccountAccessRole.
provider "aws" {
  alias  = "workloads_dev"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["workloads_dev"]}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.default_tags }
}
