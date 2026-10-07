resource "aws_key_pair" "admin" {
  key_name   = "${local.name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_instance" "app" {
  ami                     = coalesce(var.ami_id, data.aws_ami.ubuntu.id)
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.public.id
  vpc_security_group_ids  = [aws_security_group.app.id]
  key_name                = aws_key_pair.admin.key_name
  iam_instance_profile    = aws_iam_instance_profile.app.name
  disable_api_termination = var.termination_protection
  monitoring              = false

  dynamic "credit_specification" {
    for_each = data.aws_ec2_instance_type.selected.burstable_performance_supported ? [var.cpu_credits] : []

    content {
      cpu_credits = credit_specification.value
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name}-root"
    }
  }

  tags = {
    Name = local.name
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = {
    Name = local.name
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
