# -----------------------------------------------------------------------------
# Per-account GitHub OIDC deploy roles (ADR-0005 §1-2).
# dev + shared-services trust the main branch; prod requires the `prod`
# GitHub Environment (human approval gate).
# -----------------------------------------------------------------------------

module "oidc_shared_services" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.shared_services }

  role_name  = local.deploy_role_name
  trust_subs = [local.sub_main]
  policy_arn = var.deploy_role_policy_arn
}

module "oidc_workloads_dev" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.workloads_dev }

  role_name  = local.deploy_role_name
  trust_subs = [local.sub_main]
  policy_arn = var.deploy_role_policy_arn
}

module "oidc_workloads_prod" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.workloads_prod }

  role_name  = local.deploy_role_name
  trust_subs = [local.sub_prod]
  policy_arn = var.deploy_role_policy_arn
}
