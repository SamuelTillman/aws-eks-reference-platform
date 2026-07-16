# -----------------------------------------------------------------------------
# Reusable VPC: 3-AZ public/private subnets, IGW, optional per-AZ NAT (egress
# VPC), per-AZ private route tables. EKS-ready subnet tags. TGW attachment and
# the private default route are wired by the root stack (increment 2).
# -----------------------------------------------------------------------------

locals {
  # Private /19 per AZ (index 0,1,2 -> 10.x.0.0/19, /19, /19); large for EKS pods.
  private_cidrs = [for i, az in var.azs : cidrsubnet(var.cidr_block, 3, i)]
  # Public /24 per AZ, packed near the top of the /16 to avoid the /19s.
  public_cidrs = [for i, az in var.azs : cidrsubnet(var.cidr_block, 8, 240 + i)]

  eks_tags = var.eks_cluster_tag == "" ? {} : {
    "kubernetes.io/cluster/${var.eks_cluster_tag}" = "shared"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# --- Subnets ----------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.public_cidrs[each.value]
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.eks_tags, {
    Name                     = "${var.name}-public-${each.key}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.private_cidrs[each.value]

  tags = merge(var.tags, local.eks_tags, {
    Name                              = "${var.name}-private-${each.key}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# --- Public routing ---------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- NAT (egress VPC only) --------------------------------------------------

resource "aws_eip" "nat" {
  for_each = var.create_nat_gateways ? aws_subnet.public : {}
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each      = var.create_nat_gateways ? aws_subnet.public : {}
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# --- Private routing (one RT per AZ) ----------------------------------------
# Default route: NAT for the egress VPC; the root stack adds a TGW route for
# workload VPCs (increment 2).

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
  tags     = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each               = var.create_nat_gateways ? aws_subnet.private : {}
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
