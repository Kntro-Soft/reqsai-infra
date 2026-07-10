# Minimal SSM-only bastion for ad-hoc access to the private RDS instance —
# no SSH key, no public IP, no inbound rules at all. Access is entirely via
# IAM + the SSM agent's outbound connection (through the NAT gateway), using
# `aws ssm start-session ... --document-name AWS-StartPortForwardingSessionToRemoteHost`
# to tunnel a local port to the RDS endpoint. Cheapest instance type since it
# does nothing but relay a TCP tunnel on demand.

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_iam_policy_document" "bastion_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "reqsai-${var.environment}-bastion"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume_role.json
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "reqsai-${var.environment}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_security_group" "bastion" {
  name        = "reqsai-${var.environment}-bastion"
  description = "SSM-only bastion: no ingress, egress limited to Postgres + HTTPS (SSM endpoints)"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Postgres to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS for the SSM agent (via NAT gateway)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "rds_ingress_from_bastion" {
  type                     = "ingress"
  description              = "Postgres from the SSM bastion (ad-hoc DB access)"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = false

  tags = {
    Name = "reqsai-${var.environment}-bastion"
  }
}

output "bastion_instance_id" {
  description = "SSM target for the DB tunnel: aws ssm start-session --target <this> --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=<rds_address>,portNumber=5432,localPortNumber=5432"
  value       = aws_instance.bastion.id
}
