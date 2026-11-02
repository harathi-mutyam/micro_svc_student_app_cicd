variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "Unique EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
}

variable "admin_cidr" {
  description = "Public IPv4 CIDR for EKS API access"
  type        = string

  validation {
    condition = (
      can(cidrhost(var.admin_cidr, 0)) &&
      can(regex("^[0-9.]+/32$", var.admin_cidr))
    )
    error_message = "Enter a valid IPv4 CIDR ending with /32."
  }
}

variable "node_instance_type" {
  type = string
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}
