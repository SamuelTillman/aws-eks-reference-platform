# -----------------------------------------------------------------------------
# GitHub Actions OIDC federation: zero stored credentials.
#
# GitHub Actions assumes an IAM role via OIDC; no access keys exist.
# Trust is scoped to this specific repository.
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's OIDC cert chain automatically; the API still
  # requires a thumbprint but it's no longer critical for security.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.tags
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope trust to this repo via `sub` (AWS requires the trust to condition on
    # `sub` or `job_workflow_ref`, so the `repository` claim alone is rejected).
    # Accounts that emit immutable-ID OIDC subjects produce
    # `repo:OWNER@<owner_id>/REPO@<repo_id>:*`; others produce the plain
    # `repo:OWNER/REPO:*`. Set github_owner_id/github_repo_id (public numeric IDs,
    # not account IDs) to match the immutable form; leave empty for the plain
    # form. See docs/layer2-issues.md #2. Tighten to a branch/environment later
    # by narrowing the `:*` suffix.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        var.github_owner_id != "" && var.github_repo_id != "" ?
        "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:*" :
        "repo:${var.github_org}/${var.github_repo}:*"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.name_prefix}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600

  tags = local.tags
}

# Layer 0 scope: plan/apply against org + state. Broad for now, narrowed
# per-layer as the platform grows (see ADR log).
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
