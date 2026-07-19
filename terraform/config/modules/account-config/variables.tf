variable "name_prefix" {
  description = "Prefix for this account's Config resources"
  type        = string
}

variable "bucket_name" {
  description = "Central Config delivery bucket (in the security account)"
  type        = string
}

variable "permission_boundary_name" {
  description = "Name of the permission-boundary policy in this account (ADR-0012). Empty = no boundary."
  type        = string
  default     = ""
}
