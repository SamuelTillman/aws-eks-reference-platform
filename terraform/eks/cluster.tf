# -----------------------------------------------------------------------------
# EKS control plane (ADR-0007).
#
# API auth mode (access entries, not aws-auth), envelope-encrypted secrets,
# private endpoint + CIDR-restricted public, control-plane logs to CloudWatch.
# All resources run in workloads-dev via the provider alias.
# -----------------------------------------------------------------------------

# --- Cluster IAM role -------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  provider             = aws.workloads_dev
  name                 = "${local.cluster_name}-cluster"
  assume_role_policy   = data.aws_iam_policy_document.cluster_assume.json
  permissions_boundary = local.permission_boundary_arn
}

resource "aws_iam_role_policy_attachment" "cluster" {
  provider   = aws.workloads_dev
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- Secrets envelope encryption key ----------------------------------------

resource "aws_kms_key" "secrets" {
  provider = aws.workloads_dev

  description             = "Envelope encryption for ${local.cluster_name} EKS secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "secrets" {
  provider      = aws.workloads_dev
  name          = "alias/${local.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# --- The cluster ------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  provider = aws.workloads_dev

  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.public_access_cidrs) > 0
    public_access_cidrs     = var.public_access_cidrs
  }

  # API mode: identities are granted via aws_eks_access_entry, not aws-auth.
  # The creator (assumed OrganizationAccountAccessRole) is bootstrapped as admin.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.enable_control_plane_logs ? [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ] : []

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# --- IRSA OIDC provider (for add-ons that still need IRSA) -------------------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  provider = aws.workloads_dev

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

# --- Access entries: extra cluster admins (ADR-0007) ------------------------

resource "aws_eks_access_entry" "admin" {
  provider      = aws.workloads_dev
  for_each      = toset(var.cluster_admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  provider      = aws.workloads_dev
  for_each      = toset(var.cluster_admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
