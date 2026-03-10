module "machines" {
  source = "./modules/ec2"

  instance_count       = local.instances_per_region
  iam_instance_profile = local.iam_instance_profile
  user_data            = local.user_data
  instance_type        = local.instance_type
  volume_size_gb       = local.volume_size_gb
  ssh_keypair_name     = local.key_name
  fleet_valid_until    = local.fleet_valid_until
  ssh_public_key       = tls_private_key.private_key.public_key_openssh

  providers = {
    aws = aws
  }

  for_each = toset(local.regions)
  region = each.key
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
