resource "aws_s3_bucket" "ibr_bucket" {
  bucket        = "ibr-data-aws"
  provider      = aws.europa
  force_destroy = false

  acl = "private"

  tags = {
    Name = "ibr-dataset"
  }
}
