variable "name" {
  description = "Name of the permission-boundary managed policy (same name in every account it is created in)"
  type        = string
  default     = "refplatform-permission-boundary"
}

variable "tags" {
  description = "Tags for the boundary policy"
  type        = map(string)
  default     = {}
}
