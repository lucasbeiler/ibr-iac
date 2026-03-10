locals {
  iam_instance_profile = aws_iam_instance_profile.instance_profile.id
  user_data            = base64encode(templatefile("startup_script.sh", { S3_NAME = aws_s3_bucket.ibr_bucket.id, S3_REGION = aws_s3_bucket.ibr_bucket.region }))
  instance_type        = "t3.nano"
  volume_size_gb       = 10
  instances_per_region = 5
  key_name             = "ec2_ssh_key"
  fleet_valid_until    = "2026-04-10T00:00:00Z"
  ibr_bucket_name      = "ibr-data-aws-202603"
  ibr_bucket_region    = "eu-north-1"
  regions              = ["us-west-1", "us-east-1", "me-south-1", "me-central-1", "il-central-1"]
}
