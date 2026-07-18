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
    key          = "networking/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

locals {
  default_tags = {
    Project   = var.name_prefix
    ManagedBy = "terraform"
    Layer     = "1-networking"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.default_tags }
}

provider "aws" {
  alias  = "shared_services"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["shared_services"]}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.default_tags }
}

provider "aws" {
  alias  = "workloads_dev"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["workloads_dev"]}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.default_tags }
}

provider "aws" {
  alias  = "workloads_prod"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["workloads_prod"]}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.default_tags }
}

# Security account: owns the central VPC flow-logs archive (bucket + KMS key).
# Kept separate from the CloudTrail audit bucket so workload accounts never gain
# write access to the tamper-isolated audit trail (ADR-0004 §5, ADR-0006).
provider "aws" {
  alias  = "security"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.org.outputs.account_ids["security"]}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.default_tags }
}
