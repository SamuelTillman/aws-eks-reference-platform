# -----------------------------------------------------------------------------
# External Secrets Operator prerequisites (ADR-0016).
#
# ESO runs in-cluster and syncs AWS Secrets Manager values into Kubernetes
# Secrets. It authenticates with EKS Pod Identity (ADR-0007), the same mechanism
# Karpenter uses, so there is no IRSA annotation and no stored credential.
#
# Secret placement: this first secret is cluster-scoped (Grafana's admin) and so
# lives with the cluster, rotating on every rebuild. Secrets that must OUTLIVE a
# teardown belong in an always-on stack; the ClusterSecretStore reads the whole
# prefix either way.
#
# recovery_window_in_days = 0 is load-bearing: Secrets Manager's default 7-30 day
# soft delete would leave the name reserved after a teardown, and the next
# rebuild would fail with "already scheduled for deletion". Zero means the name
# frees immediately, which is what a rebuildable platform needs.
# -----------------------------------------------------------------------------

locals {
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"
  secret_prefix       = "${var.name_prefix}/${local.cluster_name}"
}

# --- The first managed secret: Grafana's admin credential --------------------

resource "random_password" "grafana_admin" {
  length           = 32
  special          = true
  override_special = "-_.~"
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  provider = aws.workloads_dev

  name                    = "${local.secret_prefix}/grafana-admin"
  description             = "Grafana admin credential, synced into the cluster by External Secrets (ADR-0016)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  provider = aws.workloads_dev

  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  })
}

# --- ESO controller identity (Pod Identity) ----------------------------------

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  provider             = aws.workloads_dev
  name                 = "${local.cluster_name}-external-secrets"
  assume_role_policy   = data.aws_iam_policy_document.eso_assume.json
  permissions_boundary = local.permission_boundary_arn
}

# Read-only, and scoped to this platform's secret prefix rather than account-wide.
resource "aws_iam_role_policy" "external_secrets" {
  provider = aws.workloads_dev
  name     = "read-platform-secrets"
  role     = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPlatformSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${local.workloads_dev_account_id}:secret:${local.secret_prefix}/*"
      },
      {
        Sid      = "ListSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:ListSecrets"
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  provider        = aws.workloads_dev
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.eso_namespace
  service_account = local.eso_service_account
  role_arn        = aws_iam_role.external_secrets.arn
}
