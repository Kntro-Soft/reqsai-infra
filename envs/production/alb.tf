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

# Redirects to HTTPS now that a real certificate exists — no traffic is
# ever forwarded to the app in plaintext from the internet.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.reqsai_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.reqsai_api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reqsai_api.arn
  }
}
