resource "aws_launch_template" "voting_nodes" {
  name_prefix = "voting-eks-nodes-"

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name    = "voting-eks-worker"
      Project = "final-voting-cicd"
    }
  }
}
