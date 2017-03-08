variable "project_name" {}
variable "access_key" {}
variable "secret_key" {}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-west-1"
}
variable "aws_az" {
  default = "all"
}
variable "want_ha" {
  default = "1"
}

variable "public_key_path" {
  description = <<DESCRIPTION
Path to the SSH public key to be used for authentication.
Ensure this keypair is added to your local SSH agent so provisioners can
connect.

Example: ~/.ssh/terraform.pub
DESCRIPTION
default = "~/.ssh/2tier-apache_rsa.pub"
}

variable "key_name" {
  description = "Desired name of AWS key pair"
  default = "2tier-apache"
}
variable "vpc_name" {
  description = "Desired name of vpc to create"
  default = "2tier-apache"
}

variable "vpc_cidr_block" {
  description = "Desired cidr block of vpc to create"
  default = "192.168.1.0/24"
}

#variable "aws_region" {
#  description = "AWS region to launch servers."
#  default     = "us-west-1"
#}


# variable "aws_az" {
#  description = "AWS availability zones to launch servers."
#  default     = {
#    "0" = "us-west-1a"
#    "1" = "us-west-1b"
#  }
#}

# Ubuntu Precise 16.04 LTS (x64) With Apache and Dan's web page
variable "aws_amis" {
  default = {
    us-west-1 = "ami-9698c7f6"
  }
}
