resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.voting.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_node_group.voting]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.voting.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_node_group.voting]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.voting.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.voting]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.voting.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.voting]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.voting.name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.ebs_csi
  ]
}
