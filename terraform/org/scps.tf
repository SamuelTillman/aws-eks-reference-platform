# -----------------------------------------------------------------------------
# Service Control Policies: the starter guardrail set.
#
# Philosophy: keep controls few, valuable, and firm. SCPs are a ceiling,
# not a permission grant; keep them small and readable.
# -----------------------------------------------------------------------------

# 1. Deny root user actions in all member accounts
data "aws_iam_policy_document" "deny_root" {
  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
}

resource "aws_organizations_policy" "deny_root" {
  name        = "deny-root-user"
  description = "Root user is never used in member accounts"
  content     = data.aws_iam_policy_document.deny_root.json
}

# 2. Region allowlist (global services exempted)
data "aws_iam_policy_document" "region_allowlist" {
  statement {
    sid       = "DenyOutsideAllowedRegions"
    effect    = "Deny"
    resources = ["*"]

    not_actions = [
      "iam:*",
      "organizations:*",
      "sts:*",
      "cloudfront:*",
      "route53:*",
      "route53domains:*",
      "support:*",
      "budgets:*",
      "ce:*",
      "waf:*",
      "wafv2:*",
      "shield:*",
      "trustedadvisor:*",
      "health:*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_organizations_policy" "region_allowlist" {
  name        = "region-allowlist"
  description = "Workloads run only in approved regions"
  content     = data.aws_iam_policy_document.region_allowlist.json
}

# 3. Deny members leaving the organization
data "aws_iam_policy_document" "deny_leave_org" {
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_leave_org" {
  name        = "deny-leave-org"
  description = "Member accounts cannot remove themselves from the org"
  content     = data.aws_iam_policy_document.deny_leave_org.json
}

# --- Attachments: apply all three to every OU at the top level --------------

locals {
  guardrail_policies = {
    deny_root        = aws_organizations_policy.deny_root.id
    region_allowlist = aws_organizations_policy.region_allowlist.id
    deny_leave_org   = aws_organizations_policy.deny_leave_org.id
  }

  target_ous = {
    security       = aws_organizations_organizational_unit.security.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    workloads      = aws_organizations_organizational_unit.workloads.id
  }

  attachments = {
    for pair in setproduct(keys(local.guardrail_policies), keys(local.target_ous)) :
    "${pair[0]}-${pair[1]}" => {
      policy_id = local.guardrail_policies[pair[0]]
      target_id = local.target_ous[pair[1]]
    }
  }
}

resource "aws_organizations_policy_attachment" "guardrails" {
  for_each  = local.attachments
  policy_id = each.value.policy_id
  target_id = each.value.target_id
}
