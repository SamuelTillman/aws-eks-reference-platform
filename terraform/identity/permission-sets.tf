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
    # The console/bootstrap-default admin set, imported so it is under IaC and can
    # be bounded (ADR-0012). Kept at its live PT1H session.
    AdministratorAccess = {
      description = "Full administrative access (console-default set, managed under ADR-0012)"
      policy_arn  = "arn:aws:iam::aws:policy/AdministratorAccess"
      session     = "PT1H"
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

# Permission boundaries on the privileged human permission sets (ADR-0012 phase 2).
# A customer-managed boundary, resolved per assigned account, so the policy must
# exist in every account these sets reach (seeded by bootstrap/cicd/security).
# Even a full-admin human session then cannot mint IAM users/keys, disable the
# audit backbone, leave the org, weaken the boundary, or create an unbounded role.
# OrganizationAccountAccessRole and management root remain the unbounded
# break-glass paths (ADR-0012). ReadOnly/Billing are already minimal, not bounded.
resource "aws_ssoadmin_permissions_boundary_attachment" "bounded" {
  for_each = toset(["Administrator", "AdministratorAccess", "PowerUser"])

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = "${var.name_prefix}-permission-boundary"
    }
  }
}
