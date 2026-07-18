variable "name" {
  description = "VPC name (e.g. workloads-dev, egress)"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR (a /16 from the platform IPAM plan)"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "create_nat_gateways" {
  description = "Create per-AZ NAT gateways with a default route from private subnets (egress VPC only). Workload VPCs egress via the Transit Gateway instead."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Collapse the NAT tier to one gateway in the first AZ instead of one per AZ. Cheaper (saves the other AZs' hourly cost) but egress is no longer AZ-independent. For dev/reference; prod keeps per-AZ HA. See ADR-0008."
  type        = bool
  default     = false
}

variable "gateway_endpoint_services" {
  description = "Gateway VPC endpoints to create (free)"
  type        = list(string)
  default     = ["s3", "dynamodb"]
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints (ECR/STS/CloudWatch Logs) so EKS nodes reach these services without traversing NAT/TGW. Each carries an hourly per-AZ cost, so off by default (ADR-0006)."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "Interface endpoint services to create when enable_interface_endpoints is true"
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "logs"]
}

variable "enable_flow_logs" {
  description = "Create a flow log for this VPC delivering to flow_log_destination_arn"
  type        = bool
  default     = false
}

variable "flow_log_destination_arn" {
  description = "S3 bucket ARN for VPC flow logs (used when enable_flow_logs is true)"
  type        = string
  default     = ""
}

variable "eks_cluster_tag" {
  description = "If set, tag subnets with kubernetes.io/cluster/<value>=shared and the ELB role tags for EKS discovery"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
