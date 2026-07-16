# -----------------------------------------------------------------------------
# Permission sets: the reusable access levels assigned to groups per account.
# One AWS managed policy each, kept deliberately small (ADR-0004 §7).
# -----------------------------------------------------------------------------

locals {
  permission_sets = {
    Administrator = {
      description = "Full administrative access"
      policy_arn  = "arn:aws:iam::aws:policy/AdministratorAccess"
      session     = "PT8H"
    }
    PowerUser = {
      description = "Full access except IAM and Organizations management"
      policy_arn  = "arn:aws:iam::aws:policy/PowerUserAccess"
      session     = "PT8H"
    }
    ReadOnly = {
      description = "Read-only access across services"
      policy_arn  = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session     = "PT4H"
    }
    Billing = {
      description = "Billing and cost management"
      policy_arn  = "arn:aws:iam::aws:policy/job-function/Billing"
      session     = "PT4H"
    }
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.sso_instance_arn
  session_duration = each.value.session
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_sets

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arn = each.value.policy_arn
}
