# -----------------------------------------------------------------------------
# Reusable platform permission boundary (ADR-0012).
#
# A CEILING policy, not a grant. It allows everything, then hard-denies the
# handful of actions no privileged principal on this platform should ever have:
# minting IAM users/keys, disabling the audit backbone, leaving the org, weakening
# the boundary, or creating a role WITHOUT this boundary (escalation guard).
#
# Instantiate once per account (a boundary is referenced by an in-account ARN),
# passing the account's provider. The ARN is constructed from caller identity so
# the policy document can reference itself without a circular dependency.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name}"
}

data "aws_iam_policy_document" "boundary" {
  # The ceiling allows everything; the principal's own policy is what actually
  # grants. Effective permissions = principal policy INTERSECT this boundary.
  statement {
    sid       = "CeilingAllowAll"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Zero stored credentials: no IAM users, no long-lived keys, ever (hard rule).
  statement {
    sid    = "DenyIamUsersAndLongLivedCreds"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:CreateServiceSpecificCredential",
      "iam:UploadSSHPublicKey",
      "iam:UploadServerCertificate",
    ]
    resources = ["*"]
  }

  # Cannot go dark on the audit/security backbone. Mirrors the deny-disable-audit
  # SCP (ADR-0009) at the role level, defense in depth if the SCP is detached.
  statement {
    sid    = "DenyAuditTampering"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:DeleteConfigurationAggregator",
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers",
      "securityhub:DisableSecurityHub",
      "securityhub:DisassociateFromAdministratorAccount",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyLeaveOrg"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization", "account:CloseAccount"]
    resources = ["*"]
  }

  # Cannot weaken or delete this boundary policy itself.
  statement {
    sid    = "ProtectBoundaryPolicy"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicy",
    ]
    resources = [local.boundary_arn]
  }

  # Cannot strip the boundary off any role.
  statement {
    sid       = "DenyRemoveBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  # Escalation guard: any role this principal creates, or any boundary it sets,
  # must be THIS boundary. A bounded admin cannot mint an unbounded (or
  # weaker-bounded) role to escape the ceiling.
  statement {
    sid       = "RequireBoundaryOnRoleCreate"
    effect    = "Deny"
    actions   = ["iam:CreateRole"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid       = "RequireBoundaryOnPut"
    effect    = "Deny"
    actions   = ["iam:PutRolePermissionsBoundary"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name        = var.name
  description = "Platform permission boundary (ADR-0012): ceiling on privileged principals."
  policy      = data.aws_iam_policy_document.boundary.json
  tags        = var.tags
}
