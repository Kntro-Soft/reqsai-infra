data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Well-known, community-maintained module — avoids hand-rolling subnets/route
# tables/NAT gateways from scratch. Pinned to a specific minor version.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "reqsai-${var.environment}"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  # ECS tasks (private subnets) and RDS (database subnets) need outbound
  # internet access (pull images, call external APIs) without being
  # publicly reachable. Single NAT gateway is a deliberate cost tradeoff
  # (~$32/mo instead of ~$64/mo for 2 AZs): if that AZ goes down, private
  # subnets in the other AZ lose internet egress until it recovers, but the
  # app stays reachable through the ALB. Revisit if uptime requirements grow.
  enable_nat_gateway = true
  single_nat_gateway = true

  create_database_subnet_group = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}
