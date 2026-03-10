data "aws_ami" "alpine" {
  most_recent      = true
  owners           = ["538276064493"]
  region           = var.region

  filter {
    name   = "name"
    values = ["alpine-*-x86_64-uefi-cloudinit-r0"]
  }
}
