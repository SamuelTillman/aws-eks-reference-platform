variable "aws_region" {
  description = "Home region for the platform"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix/tag value for platform resources"
  type        = string
  default     = "refplatform"
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform remote state (embeds the mgmt account ID; supply via gitignored tfvars)"
  type        = string
}

variable "namespace" {
  description = "Namespace ArgoCD is installed into"
  type        = string
  default     = "argocd"
}

# Chart versions are intentionally required (no default): pin the current ones at
# apply time. Find them with:
#   helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
#   helm search repo argo/argo-cd argo/argocd-apps --versions | head
variable "argocd_chart_version" {
  description = "Pinned argo-cd Helm chart version (verify current before apply)"
  type        = string
}

variable "argocd_apps_chart_version" {
  description = "Pinned argocd-apps Helm chart version (verify current before apply)"
  type        = string
}

# --- GitOps source (app-of-apps) --------------------------------------------

variable "gitops_repo_url" {
  description = "Git repo ArgoCD reads Applications from. Public repo = no credentials needed."
  type        = string
  default     = "https://github.com/SamuelTillman/aws-eks-reference-platform.git"
}

variable "gitops_path" {
  description = "Path in the repo holding child Application manifests"
  type        = string
  default     = "gitops/apps"
}

variable "gitops_revision" {
  description = "Git revision the root app tracks"
  type        = string
  default     = "main"
}
