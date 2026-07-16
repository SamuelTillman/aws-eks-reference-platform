# -----------------------------------------------------------------------------
# Transit Gateway hub + centralized-egress routing (ADR-0006).
#
# Flow: workload private subnet --0/0--> TGW --(workloads RT: 0/0)--> egress
# attachment --> egress VPC private RT --0/0--> NAT --> IGW --> internet.
# Return: NAT --(egress public RT: workload CIDR)--> TGW --(egress RT)--> workload.
# dev and prod share the workloads RT but have no route to each other = isolated.
# -----------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "this" {
  provider    = aws.shared_services
  description = "${var.name_prefix} organization transit gateway"

  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = { Name = "${var.name_prefix}-tgw" }
}

# --- Share the TGW to the workload accounts (org sharing enabled out-of-band) --

resource "aws_ram_resource_share" "tgw" {
  provider                  = aws.shared_services
  name                      = "${var.name_prefix}-tgw"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "tgw" {
  provider           = aws.shared_services
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "workloads" {
  provider           = aws.shared_services
  for_each           = toset([local.account_ids["workloads_dev"], local.account_ids["workloads_prod"]])
  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# --- Attachments (each in its owning account) --------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  provider           = aws.shared_services
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc_egress.vpc_id
  subnet_ids         = module.vpc_egress.private_subnet_ids

  tags = { Name = "${var.name_prefix}-egress" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev" {
  provider           = aws.workloads_dev
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc_dev.vpc_id
  subnet_ids         = module.vpc_dev.private_subnet_ids

  tags       = { Name = "${var.name_prefix}-dev" }
  depends_on = [aws_ram_principal_association.workloads]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod" {
  provider           = aws.workloads_prod
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc_prod.vpc_id
  subnet_ids         = module.vpc_prod.private_subnet_ids

  tags       = { Name = "${var.name_prefix}-prod" }
  depends_on = [aws_ram_principal_association.workloads]
}

# --- TGW route tables (owner-managed, in shared-services) --------------------

resource "aws_ec2_transit_gateway_route_table" "workloads" {
  provider           = aws.shared_services
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name_prefix}-workloads" }
}

resource "aws_ec2_transit_gateway_route_table" "egress" {
  provider           = aws.shared_services
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name_prefix}-egress" }
}

resource "aws_ec2_transit_gateway_route_table_association" "dev" {
  provider                       = aws.shared_services
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
}

resource "aws_ec2_transit_gateway_route_table_association" "prod" {
  provider                       = aws.shared_services
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
}

resource "aws_ec2_transit_gateway_route_table_association" "egress" {
  provider                       = aws.shared_services
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

# Workloads RT: everything egresses via the egress attachment.
resource "aws_ec2_transit_gateway_route" "workloads_default" {
  provider                       = aws.shared_services
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.workloads.id
}

# Egress RT: return traffic to each workload via its own attachment.
resource "aws_ec2_transit_gateway_route" "egress_to_dev" {
  provider                       = aws.shared_services
  destination_cidr_block         = local.cidrs.dev
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

resource "aws_ec2_transit_gateway_route" "egress_to_prod" {
  provider                       = aws.shared_services
  destination_cidr_block         = local.cidrs.prod
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

# --- VPC route-table wiring to the TGW --------------------------------------

# Workload private subnets default-route to the TGW.
resource "aws_route" "dev_default_tgw" {
  provider               = aws.workloads_dev
  for_each               = module.vpc_dev.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dev]
}

resource "aws_route" "prod_default_tgw" {
  provider               = aws.workloads_prod
  for_each               = module.vpc_prod.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.prod]
}

# Egress VPC public subnets (NAT lives here) send return traffic back via TGW.
resource "aws_route" "egress_return_dev" {
  provider               = aws.shared_services
  route_table_id         = module.vpc_egress.public_route_table_id
  destination_cidr_block = local.cidrs.dev
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress]
}

resource "aws_route" "egress_return_prod" {
  provider               = aws.shared_services
  route_table_id         = module.vpc_egress.public_route_table_id
  destination_cidr_block = local.cidrs.prod
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress]
}
