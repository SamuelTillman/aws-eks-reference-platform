# -----------------------------------------------------------------------------
# Identity Center groups. Access is granted to groups, never directly to users.
# Membership of platform-admins can be seeded from var.platform_admin_usernames.
# -----------------------------------------------------------------------------

locals {
  groups = {
    "platform-admins" = "Platform administrators, full access across all accounts"
    "developers"      = "Application developers, power access in dev, read-only in prod"
    "auditors"        = "Security auditors, read-only across all accounts"
    "billing"         = "Billing and cost management"
  }
}

resource "aws_identitystore_group" "this" {
  for_each = local.groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value
}

# Look up existing SSO users named in the variable, then add them to
# platform-admins. Empty variable => no memberships managed here.
data "aws_identitystore_user" "platform_admins" {
  for_each = toset(var.platform_admin_usernames)

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value
    }
  }
}

resource "aws_identitystore_group_membership" "platform_admins" {
  for_each = data.aws_identitystore_user.platform_admins

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this["platform-admins"].group_id
  member_id         = each.value.user_id
}
