# -----------------------------------------------------------------------------
# Managed EKS add-ons (ADR-0007).
#
# Only the cluster-critical add-ons are Terraform-managed. Everything above this
# line (Cilium/mesh, ArgoCD, observability, Kyverno, Backstage) is delivered by
# ArgoCD in later increments, this stack stops at a schedulable cluster.
# Add-on versions default to the cluster version's recommended release.
# -----------------------------------------------------------------------------

# Pod Identity agent, the default workload-IAM mechanism (ADR-0007).
resource "aws_eks_addon" "pod_identity" {
  provider     = aws.workloads_dev
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# VPC CNI with prefix delegation, so a node packs many pod IPs from the subnet
# (ADR-0006 sized the /19s for this).
resource "aws_eks_addon" "vpc_cni" {
  provider     = aws.workloads_dev
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "aws_eks_addon" "kube_proxy" {
  provider     = aws.workloads_dev
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# CoreDNS needs schedulable capacity, wait for the system node group.
resource "aws_eks_addon" "coredns" {
  provider     = aws.workloads_dev
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}
