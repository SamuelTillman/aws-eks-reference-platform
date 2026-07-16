# -----------------------------------------------------------------------------
# Gateway VPC endpoints (S3, DynamoDB), free, keep that traffic off NAT/TGW.
# Associated with every private route table.
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
