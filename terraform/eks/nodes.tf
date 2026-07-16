# -----------------------------------------------------------------------------
# System managed node group (ADR-0007 decision 2).
#
# A small, stable tier that runs cluster-critical add-ons and, in a later
# increment, the Karpenter controller, which then autoscales workload capacity.
# Nodes live in the dev VPC's private subnets and egress via the TGW (ADR-0006).
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  provider           = aws.workloads_dev
  name               = "${local.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  provider = aws.workloads_dev
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # SSM so nodes are reachable without SSH/bastion (matches the no-keys rule).
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "system" {
  provider = aws.workloads_dev

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "platform.refplatform/tier" = "system"
  }

  depends_on = [aws_iam_role_policy_attachment.node]

  # Desired size drifts as the cluster autoscales; don't fight it on re-apply.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
