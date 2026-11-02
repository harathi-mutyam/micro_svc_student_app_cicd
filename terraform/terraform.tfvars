# AWS Region
aws_region = "eu-north-1"

# EKS Cluster
cluster_name       = "voting-cluster"
kubernetes_version = "1.34"

# EC2 Public IP for administrative access
admin_cidr = "16.170.110.199/32"

# EKS Worker Nodes (example values)
node_instance_type = "c7i-flex.large"
node_desired_size  = 2
node_min_size      = 1
node_max_size      = 2
