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

# 3. Deny members leaving the organization or self-closing their account.
#    Supersedes the console-created "DenyLeaveAndCloseAccount" SCP (attached to
#    Root during bootstrap), which was removed so this managed policy is the
#    single, in-code source of truth for both controls. See ADR-0003.
data "aws_iam_policy_document" "deny_leave_org" {
  statement {
    sid    = "DenyLeaveAndCloseAccount"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "account:CloseAccount",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_leave_org" {
  name        = "deny-leave-and-close"
  description = "Member accounts cannot leave the org or close themselves"
  content     = data.aws_iam_policy_document.deny_leave_org.json
}

# 4. Deny disabling the audit / security backbone (ADR-0009).
#    Blocks stopping or deleting CloudTrail, Config, GuardDuty, and Security Hub
#    so no workload role, SSO human, or compromised app credential can go dark on
#    the audit trail. The OrganizationAccountAccessRole is exempt: Terraform and
#    the gated lifecycle workflow (ADR-0008) act through it, including the
#    deliberate `security` stand-down. Hard immutability of the log DATA comes
#    from S3 Object Lock, not this SCP.
data "aws_iam_policy_document" "deny_disable_audit" {
  statement {
    sid    = "DenyDisableAuditAndSecurity"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:DeleteConfigurationAggregator",
      "guardduty:DeleteDetector",
      "guardduty:UpdateDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers",
      "securityhub:DisableSecurityHub",
      "securityhub:DisassociateFromAdministratorAccount",
    ]
    resources = ["*"]

    # Exempt the trusted IaC/lifecycle path so Terraform and the ADR-0008 button
    # can still manage (and deliberately stand down) these services.
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    }
  }
}

resource "aws_organizations_policy" "deny_disable_audit" {
  name        = "deny-disable-audit"
  description = "No one but the IaC path can stop/delete CloudTrail, Config, GuardDuty, Security Hub"
  content     = data.aws_iam_policy_document.deny_disable_audit.json
}

# --- Attachments: apply all four to every OU at the top level ---------------

locals {
  guardrail_policies = {
    deny_root          = aws_organizations_policy.deny_root.id
    region_allowlist   = aws_organizations_policy.region_allowlist.id
    deny_leave_org     = aws_organizations_policy.deny_leave_org.id
    deny_disable_audit = aws_organizations_policy.deny_disable_audit.id
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
