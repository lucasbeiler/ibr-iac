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

resource "aws_spot_instance_request" "instances" {
  ami = "ami-08e61ba43f1e1d9a3" # Alpine Linux
  # ami = "ami-02396cdd13e9a1257" # Amazon Linux 2023
  # provider      = aws.eua
  spot_price    = "0.03"
  instance_type = "t3.nano"
  key_name      = aws_key_pair.generated_key.key_name

  user_data = templatefile("startup_script.sh",  { S3_NAME = aws_s3_bucket.ibr_bucket.id, S3_REGION = aws_s3_bucket.ibr_bucket.region })

  root_block_device {
    volume_size = "8" # disk space (GB)
  }

  iam_instance_profile   = aws_iam_instance_profile.instance_profile.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.KEY_NAME
  public_key = tls_private_key.private_key.public_key_openssh
}
