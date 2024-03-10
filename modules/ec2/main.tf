resource "aws_security_group" "allow_all" {
  name        = "allow_everything"
  description = "Allow all traffic."
  # vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 0    # 0 (semantically equivalent to all)
    to_port          = 0    # 0 (semantically equivalent to all)
    protocol         = "-1" # "-1" (semantically equivalent to all)
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0    # 0 (semantically equivalent to all)
    to_port          = 0    # 0 (semantically equivalent to all)
    protocol         = "-1" # "-1" (semantically equivalent to all)
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_ec2_fleet" "instances" {
  valid_until = "2024-06-06T00:00:00Z"
  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.instances.id
      version            = "$Latest"
    }
  }

  target_capacity_specification {
    default_target_capacity_type = "spot"
    total_target_capacity        = 5
  }

  replace_unhealthy_instances = true
  terminate_instances         = true
}

resource "aws_launch_template" "instances" {
  image_id      = data.aws_ami.alpine.image_id
  instance_type = var.instance_type
  key_name      = var.ssh_keypair_name
  user_data     = var.user_data

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.volume_size_gb
      # volume_type = "gp2"
    }
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  vpc_security_group_ids = [aws_security_group.allow_all.id]
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.ssh_keypair_name
  public_key = var.ssh_public_key # tls_private_key.private_key.public_key_openssh
}
