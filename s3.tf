resource "aws_s3_bucket" "ibr_bucket" {
  bucket        = local.ibr_bucket_name
  region        = local.ibr_bucket_region
  force_destroy = false

  tags = {
    Name = "ibr-data-aws"
  }
}
