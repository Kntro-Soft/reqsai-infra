# --- ALB: the only piece reachable from the public internet ---
resource "aws_security_group" "alb" {
  name        = "reqsai-${var.environment}-alb"
  description = "Allows inbound HTTP/HTTPS from the internet to the ALB"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  description       = "HTTP from anywhere"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "HTTPS from anywhere"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
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
