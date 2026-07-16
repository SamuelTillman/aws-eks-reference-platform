# -----------------------------------------------------------------------------
# Account assignments: which group gets which permission set on which account.
# The matrix mirrors ADR-0004 §7. Account keys resolve to IDs via local.account_ids.
# -----------------------------------------------------------------------------

locals {
  # group => { account_key => permission_set_name }
  assignment_matrix = {
    "platform-admins" = {
      management      = "Administrator"
      security        = "Administrator"
      shared_services = "Administrator"
      workloads_dev   = "Administrator"
      workloads_prod  = "Administrator"
    }
    "developers" = {
      shared_services = "ReadOnly"
      workloads_dev   = "PowerUser"
      workloads_prod  = "ReadOnly"
    }
    "auditors" = {
      management      = "ReadOnly"
      security        = "ReadOnly"
      shared_services = "ReadOnly"
      workloads_dev   = "ReadOnly"
      workloads_prod  = "ReadOnly"
    }
    "billing" = {
      management = "Billing"
    }
  }

  # Flatten to "group:account" => assignment detail. Keys are static (known at
  # plan) so they're valid for_each keys; values may resolve after apply.
  assignments = merge([
    for group, accounts in local.assignment_matrix : {
      for account_key, ps_name in accounts :
      "${group}:${account_key}" => {
        group_id           = aws_identitystore_group.this[group].group_id
        permission_set_arn = aws_ssoadmin_permission_set.this[ps_name].arn
        account_id         = local.account_ids[account_key]
      }
    }
  ]...)
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = each.value.permission_set_arn
  principal_id       = each.value.group_id
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}
