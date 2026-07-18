# -----------------------------------------------------------------------------
# ArgoCD bootstrap (ADR-0010). Terraform installs ArgoCD and one root app; from
# there the cluster is GitOps-driven from gitops/ in this repo.
#
# Cross-account auth: run this stack as MANAGEMENT (so it can read the eks/org
# remote state from the mgmt state bucket). The Helm/Kubernetes providers then
# reach the cluster in workloads-dev by having `aws eks get-token` assume that
# account's OrganizationAccountAccessRole. NB: keep the local SSO token fresh, an
# expired token makes get-token hang (see docs/layer2-issues.md #4).
# -----------------------------------------------------------------------------

data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "org/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  cluster_name  = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_host  = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca    = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority)
  wd_account_id = data.terraform_remote_state.org.outputs.account_ids["workloads_dev"]
  wd_role_arn   = "arn:aws:iam::${local.wd_account_id}:role/OrganizationAccountAccessRole"

  exec_args = [
    "eks", "get-token",
    "--cluster-name", local.cluster_name,
    "--region", var.aws_region,
    "--role-arn", local.wd_role_arn,
  ]
}

provider "kubernetes" {
  host                   = local.cluster_host
  cluster_ca_certificate = local.cluster_ca

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.exec_args
  }
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_host
    cluster_ca_certificate = local.cluster_ca

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.exec_args
    }
  }
}
