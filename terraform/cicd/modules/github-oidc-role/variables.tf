variable "role_name" {
  description = "Name of the GitHub Actions deploy role in this account"
  type        = string
}

variable "trust_subs" {
  description = "Allowed token.actions.githubusercontent.com:sub values (StringLike)"
  type        = list(string)
}

variable "policy_arn" {
  description = "Managed policy attached to the deploy role"
  type        = string
}
