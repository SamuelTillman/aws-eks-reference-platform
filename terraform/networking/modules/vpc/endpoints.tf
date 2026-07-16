# -----------------------------------------------------------------------------
# VPC endpoints (ADR-0006 §Private AWS connectivity).
#
# Gateway endpoints (S3, DynamoDB) are free and always on. Interface endpoints
# (ECR/STS/CloudWatch Logs) let EKS nodes pull images and assume roles without
# traversing NAT/TGW, but carry an hourly per-AZ cost, off by default.
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoint_services)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}

# --- Interface endpoints (optional) -----------------------------------------

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpce"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC CIDR"
  cidr_ipv4         = var.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_all" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "Allow all egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(var.interface_endpoint_services) : []

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints[0].id]

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}
