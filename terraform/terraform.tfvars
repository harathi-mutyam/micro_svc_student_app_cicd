# AWS Region
aws_region = "eu-north-1"

# EKS Cluster
cluster_name       = "student-cluster"
kubernetes_version = "1.34"

# EC2 Public IP for administrative access
admin_cidr = "16.170.165.24/32"

# EKS Worker Nodes (example values)
node_instance_type = "c7i-flex.large"
node_desired_size  = 2
node_min_size      = 1
node_max_size      = 2
