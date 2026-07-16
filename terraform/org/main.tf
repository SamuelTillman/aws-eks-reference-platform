# -----------------------------------------------------------------------------
# Organization structure: OUs + member accounts
#
# The organization itself was created manually (docs/bootstrap.md step 3);
# everything inside it's managed here.
# -----------------------------------------------------------------------------

data "aws_organizations_organization" "this" {}

locals {
  root_id = data.aws_organizations_organization.this.roots[0].id
}

# --- Organizational Units --------------------------------------------------

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = local.root_id
}

# --- Member accounts ---------------------------------------------------------
# Root passwords are never set on vended accounts (see docs/bootstrap.md).
# close_on_deletion is intentionally false: closing an account is a human decision.

resource "aws_organizations_account" "security" {
  name      = "security"
  email     = var.account_emails["security"]
  parent_id = aws_organizations_organizational_unit.security.id
  role_name = var.org_access_role_name

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "shared_services" {
  name      = "shared-services"
  email     = var.account_emails["shared_services"]
  parent_id = aws_organizations_organizational_unit.infrastructure.id
  role_name = var.org_access_role_name

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "workloads_dev" {
  name      = "workloads-dev"
  email     = var.account_emails["workloads_dev"]
  parent_id = aws_organizations_organizational_unit.workloads.id
  role_name = var.org_access_role_name

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "workloads_prod" {
  name      = "workloads-prod"
  email     = var.account_emails["workloads_prod"]
  parent_id = aws_organizations_organizational_unit.workloads.id
  role_name = var.org_access_role_name

  lifecycle {
    ignore_changes = [role_name]
  }
}
