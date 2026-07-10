# AWS-managed, auto-updated list of CloudFront's own outbound IP ranges —
# using it instead of hardcoded CIDRs means this never goes stale as AWS
# adds/rotates CloudFront IPs.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# --- ALB: reachable only from CloudFront, not the raw internet ---
# (description left unchanged on purpose: it's immutable in AWS, so editing
# it would force-replace this security group and briefly disrupt the live ALB)
resource "aws_security_group" "alb" {
  name        = "reqsai-${var.environment}-alb"
  description = "Allows inbound HTTP/HTTPS from the internet to the ALB"
  vpc_id      = module.vpc.vpc_id
}

# No port-80 ingress rule: CloudFront's origin config (frontend.tf) is
# https-only, so it never connects to the ALB over port 80 — the listener's
# HTTP->HTTPS redirect (alb.tf) is unreachable dead config now, harmless to
# leave in place, but no rule is needed to allow traffic that never arrives.
# (Also avoids the CloudFront prefix list's ~50+ entries pushing this
# security group over AWS's default 60-rules-per-SG quota.)

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "HTTPS from CloudFront only"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  description       = "Allow the ALB to reach the ECS tasks (and anything else it needs)"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# --- ECS tasks: reachable only from the ALB, never directly from the internet ---
resource "aws_security_group" "ecs_tasks" {
  name        = "reqsai-${var.environment}-ecs-tasks"
  description = "Allows inbound traffic only from the ALB, on the app port"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  description              = "App port from the ALB"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_tasks.id
}

resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  description       = "Pull images from ECR, call external APIs (Gemini, SMTP...), reach RDS"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
}

# --- RDS: reachable only from the ECS tasks, never publicly ---
resource "aws_security_group" "rds" {
  name        = "reqsai-${var.environment}-rds"
  description = "Allows inbound Postgres traffic only from the ECS tasks"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "rds_ingress_from_ecs" {
  type                     = "ingress"
  description              = "Postgres from the ECS tasks"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.rds.id
}
