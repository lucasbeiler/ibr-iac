variable "iam_instance_profile" {
  type = string
}

variable "user_data" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "fleet_valid_until" {
  type = string
}

variable "volume_size_gb" {
  type = number
}

variable "ssh_keypair_name" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "instance_count" {
  type = number
  default = 1
}

variable "region" {
  type = string
  default = "us-east-1"
}
