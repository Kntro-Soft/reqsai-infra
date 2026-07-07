# Public entry point — the only piece of this infra reachable from the
# internet. Lives in the public subnets; everything behind it (ECS, RDS)
# stays private.
resource "aws_lb" "reqsai_api" {
  name               = "reqsai-${var.environment}-api"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

# Fargate uses awsvpc networking (each task gets its own ENI/IP), so the
# target group tracks targets by IP, not by EC2 instance id.
resource "aws_lb_target_group" "reqsai_api" {
  name        = "reqsai-${var.environment}-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTP only for now — no ACM certificate/custom domain yet. Add an HTTPS
# listener (port 443) once a domain is pointed at the ALB, and switch this
# one to redirect HTTP -> HTTPS instead of forwarding directly.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.reqsai_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reqsai_api.arn
  }
}
