data "aws_caller_identity" "current" {}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

data "aws_ec2_instance_type_offerings" "selected" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${local.ami_architecture}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name              = "reqsai-${var.environment}"
  ami_architecture  = contains(data.aws_ec2_instance_type.selected.supported_architectures, "arm64") ? "arm64" : "amd64"
  availability_zone = coalesce(var.availability_zone, sort(data.aws_ec2_instance_type_offerings.selected.locations)[0])
  memory_profile    = data.aws_ec2_instance_type.selected.memory_size >= 2048 ? "small" : "micro"
  use_route53       = var.dns_zone_name != ""
  sslip_hostname    = "${replace(aws_eip.app.public_ip, ".", "-")}.sslip.io"
  app_hostname      = local.use_route53 ? "${var.dns_record_name}.${var.dns_zone_name}" : local.sslip_hostname
  use_ssm_transport = var.enable_ssm && length(var.admin_cidrs) == 0
}
