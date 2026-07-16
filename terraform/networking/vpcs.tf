# -----------------------------------------------------------------------------
# The three VPCs (ADR-0006). The egress VPC (shared-services) owns the NAT tier;
# workload VPCs have no NAT and will egress via the Transit Gateway (increment 2).
# -----------------------------------------------------------------------------

module "vpc_egress" {
  source    = "./modules/vpc"
  providers = { aws = aws.shared_services }

  name                = "${var.name_prefix}-egress"
  cidr_block          = local.cidrs.egress
  azs                 = var.azs
  create_nat_gateways = true
}

module "vpc_dev" {
  source    = "./modules/vpc"
  providers = { aws = aws.workloads_dev }

  name            = "${var.name_prefix}-dev"
  cidr_block      = local.cidrs.dev
  azs             = var.azs
  eks_cluster_tag = "${var.name_prefix}-dev"
}

module "vpc_prod" {
  source    = "./modules/vpc"
  providers = { aws = aws.workloads_prod }

  name            = "${var.name_prefix}-prod"
  cidr_block      = local.cidrs.prod
  azs             = var.azs
  eks_cluster_tag = "${var.name_prefix}-prod"
}
