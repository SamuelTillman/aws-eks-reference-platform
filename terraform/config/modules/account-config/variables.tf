variable "name_prefix" {
  description = "Prefix for this account's Config resources"
  type        = string
}

variable "bucket_name" {
  description = "Central Config delivery bucket (in the security account)"
  type        = string
}
