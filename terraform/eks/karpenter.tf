# -----------------------------------------------------------------------------
# Karpenter AWS prerequisites (ADR-0011).
#
# The cloud-side plumbing Karpenter needs; Karpenter itself (the controller Helm
# release + NodePool/EC2NodeClass) is delivered by ArgoCD from gitops/apps/.
# Everything here runs in workloads-dev via the provider alias and is torn down
# with the cluster.
#
# Split of concerns:
#   - controller IAM role   -> assumed by the karpenter pod via EKS Pod Identity
#   - node IAM role + entry  -> assumed by Karpenter-launched EC2 nodes to join
#   - SQS queue + EventBridge -> graceful drain on spot/rebalance/health events
#   - discovery tags          -> how the EC2NodeClass finds subnets + SGs
#
# EC2 Spot service-linked role: NOT managed here. The system node group already
# runs SPOT (ADR-0007), so AWSServiceRoleForEC2Spot already exists in this
# account; creating it in Terraform would fail EntityAlreadyExists. On a fresh
# account whose first spot request is Karpenter's, create it once out of band:
#   aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
# (same defensive note as the Access Analyzer SLR, layer1-issues.md #2).
# -----------------------------------------------------------------------------

data "aws_partition" "current" {
  provider = aws.workloads_dev
}

locals {
  workloads_dev_account_id = data.terraform_remote_state.org.outputs.account_ids["workloads_dev"]
  karpenter_queue_name     = "${local.cluster_name}-karpenter"

  # EventBridge rules that feed the interruption queue. Karpenter reads these to
  # cordon+drain a node before AWS reclaims it, instead of a hard spot kill.
  karpenter_events = {
    spot_interruption = {
      source      = ["aws.ec2"]
      detail_type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance State-change Notification"]
    }
    scheduled_change = {
      source      = ["aws.health"]
      detail_type = ["AWS Health Event"]
    }
  }
}

# =============================================================================
# Node identity: Karpenter-launched nodes assume this role and join via an
# EC2_LINUX access entry (API auth mode, ADR-0007). Kept separate from the
# system managed-node-group role so the two capacity sources are decoupled.
# =============================================================================

resource "aws_iam_role" "karpenter_node" {
  provider           = aws.workloads_dev
  name               = "${local.cluster_name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json # ec2.amazonaws.com, from nodes.tf
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  provider = aws.workloads_dev
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

# Pre-created instance profile referenced by the EC2NodeClass (instanceProfile:).
# Pre-creating it keeps instance-profile management OUT of the controller policy
# (tighter least privilege), at the cost of owning its lifecycle here.
resource "aws_iam_instance_profile" "karpenter_node" {
  provider = aws.workloads_dev
  name     = "${local.cluster_name}-karpenter-node"
  role     = aws_iam_role.karpenter_node.name
}

resource "aws_eks_access_entry" "karpenter_node" {
  provider      = aws.workloads_dev
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX" # node-type entry: system:nodes mapping is automatic
}

# =============================================================================
# Controller identity: the karpenter pod authenticates via EKS Pod Identity
# (agent installed in addons.tf), no IRSA annotation needed.
# =============================================================================

data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  provider           = aws.workloads_dev
  name               = "${local.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

resource "aws_eks_pod_identity_association" "karpenter" {
  provider        = aws.workloads_dev
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# Karpenter's documented controller policy (v1), scoped to this cluster/region.
# Instance-profile CRUD is intentionally omitted (we pre-create the profile and
# set it statically on the EC2NodeClass), leaving only a read to resolve it.
resource "aws_iam_role_policy" "karpenter_controller" {
  provider = aws.workloads_dev
  name     = "karpenter-controller"
  role     = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:subnet/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                        = local.cluster_name
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                        = local.cluster_name
            "ec2:CreateAction"                                           = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*"
        Action   = "ec2:CreateTags"
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
        ]
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter_interruption.arn
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      },
      {
        Sid       = "AllowPassingInstanceRole"
        Effect    = "Allow"
        Resource  = aws_iam_role.karpenter_node.arn
        Action    = "iam:PassRole"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${local.workloads_dev_account_id}:instance-profile/*"
        Action   = "iam:GetInstanceProfile"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = aws_eks_cluster.this.arn
        Action   = "eks:DescribeCluster"
      },
    ]
  })
}

# =============================================================================
# Interruption handling: EventBridge -> SQS -> Karpenter.
# =============================================================================

resource "aws_sqs_queue" "karpenter_interruption" {
  provider                  = aws.workloads_dev
  name                      = local.karpenter_queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true # SSE-SQS at rest
}

data "aws_iam_policy_document" "karpenter_interruption_sqs" {
  statement {
    sid       = "EventBridgeAndSqsToQueue"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
  # TLS-only, matching the platform's in-transit posture (ADR-0009).
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  provider  = aws.workloads_dev
  queue_url = aws_sqs_queue.karpenter_interruption.url
  policy    = data.aws_iam_policy_document.karpenter_interruption_sqs.json
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  provider = aws.workloads_dev
  for_each = local.karpenter_events
  name     = "${local.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode({
    source        = each.value.source
    "detail-type" = each.value.detail_type
  })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  provider  = aws.workloads_dev
  for_each  = local.karpenter_events
  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "karpenter-interruption-queue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# =============================================================================
# Discovery tags: the EC2NodeClass selects subnets + security groups by this tag
# (karpenter.sh/discovery = <cluster>), so no account-specific IDs live in Git.
# =============================================================================

resource "aws_ec2_tag" "subnet_discovery" {
  provider    = aws.workloads_dev
  for_each    = toset(local.private_subnet_ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}

resource "aws_ec2_tag" "cluster_sg_discovery" {
  provider    = aws.workloads_dev
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}
