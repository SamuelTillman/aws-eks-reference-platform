# -----------------------------------------------------------------------------
# Per-account GitHub OIDC deploy roles (ADR-0005 §1-2).
# dev + shared-services trust the main branch; prod requires the `prod`
# GitHub Environment (human approval gate).
# -----------------------------------------------------------------------------

# Permission boundary (ADR-0012), one per member account (a boundary is
# referenced by an in-account ARN). Each deploy role is capped by its account's
# boundary so a compromised OIDC token cannot mint credentials, disable audit, or
# escalate via an unbounded role.
module "boundary_shared_services" {
  source    = "../modules/permission-boundary"
  providers = { aws = aws.shared_services }
  name      = "${var.name_prefix}-permission-boundary"
}

module "boundary_workloads_dev" {
  source    = "../modules/permission-boundary"
  providers = { aws = aws.workloads_dev }
  name      = "${var.name_prefix}-permission-boundary"
}

module "boundary_workloads_prod" {
  source    = "../modules/permission-boundary"
  providers = { aws = aws.workloads_prod }
  name      = "${var.name_prefix}-permission-boundary"
}

module "oidc_shared_services" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.shared_services }

  role_name                = local.deploy_role_name
  trust_subs               = [local.sub_main]
  policy_arn               = var.deploy_role_policy_arn
  permissions_boundary_arn = module.boundary_shared_services.arn
}

module "oidc_workloads_dev" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.workloads_dev }

  role_name                = local.deploy_role_name
  trust_subs               = [local.sub_main]
  policy_arn               = var.deploy_role_policy_arn
  permissions_boundary_arn = module.boundary_workloads_dev.arn
}

module "oidc_workloads_prod" {
  source    = "./modules/github-oidc-role"
  providers = { aws = aws.workloads_prod }

  role_name                = local.deploy_role_name
  trust_subs               = [local.sub_prod]
  policy_arn               = var.deploy_role_policy_arn
  permissions_boundary_arn = module.boundary_workloads_prod.arn
}
