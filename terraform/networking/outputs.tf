output "vpc_ids" {
  description = "VPC IDs by role"
  value = {
    egress = module.vpc_egress.vpc_id
    dev    = module.vpc_dev.vpc_id
    prod   = module.vpc_prod.vpc_id
  }
}

output "private_subnet_ids" {
  description = "Private subnet IDs by VPC (EKS node/pod subnets)"
  value = {
    dev  = module.vpc_dev.private_subnet_ids
    prod = module.vpc_prod.private_subnet_ids
  }
}

output "vpc_cidrs" {
  value = local.cidrs
}

output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}
