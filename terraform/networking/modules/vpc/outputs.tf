output "vpc_id" {
  value = aws_vpc.this.id
}

output "cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "private_route_table_ids" {
  description = "Per-AZ private route table IDs (root stack adds TGW default routes here)"
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "public_route_table_id" {
  description = "Public route table ID (egress VPC: root stack adds return routes to workload CIDRs via TGW)"
  value       = aws_route_table.public.id
}
