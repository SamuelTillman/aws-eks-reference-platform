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
  provider             = aws.workloads_dev
  name                 = "${local.cluster_name}-node"
  assume_role_policy   = data.aws_iam_policy_document.node_assume.json
  permissions_boundary = local.permission_boundary_arn
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

# Launch template: enforce IMDSv2 and encrypt the node root volume (ADR-0009).
# No image_id, so EKS still supplies the AMI selected by the node group's
# ami_type; disk_size moves here as an encrypted block device mapping.
resource "aws_launch_template" "node" {
  provider    = aws.workloads_dev
  name_prefix = "${local.cluster_name}-node-"

  # IMDSv2 required + hop limit 1: a pod or SSRF cannot reach the node role
  # credentials via the instance metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypted root EBS volume (AL2023 root device is /dev/xvda).
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.node_disk_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { "platform.refplatform/tier" = "system" }
  }
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

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

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
