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

variable "gateway_endpoint_services" {
  description = "Gateway VPC endpoints to create (free)"
  type        = list(string)
  default     = ["s3", "dynamodb"]
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
