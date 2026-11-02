output "cluster_name" {
  value = aws_eks_cluster.voting.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.voting.endpoint
}

output "node_group_name" {
  value = aws_eks_node_group.voting.node_group_name
}

output "vpc_id" {
  value = aws_vpc.voting.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.voting.name}"
}
