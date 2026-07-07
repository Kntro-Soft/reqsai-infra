# 0.25 vCPU / 0.5 GB, as decided for cost. Fargate cpu/memory are in
# specific paired units: "256" = 0.25 vCPU, "512" = 0.5 GB.
resource "aws_ecs_task_definition" "reqsai_api" {
  family                   = "reqsai-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required by Fargate: each task gets its own ENI/IP
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "reqsai-api"
      image     = "${aws_ecr_repository.reqsai_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      # Plain, non-sensitive config — safe to see in the task definition JSON.
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "APP_URL", value = "http://${aws_lb.reqsai_api.dns_name}" },
        { name = "FRONTEND_URL", value = var.frontend_url },
        { name = "DB_HOST", value = aws_db_instance.reqsai.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.reqsai.port) },
        { name = "DB_NAME", value = aws_db_instance.reqsai.db_name },
        { name = "DB_USERNAME", value = aws_db_instance.reqsai.username },
        { name = "EMAIL_PROVIDER", value = "gmail" },
        { name = "MAIL_HOST", value = "smtp.gmail.com" },
        { name = "MAIL_PORT", value = "587" },
        { name = "STT_PROVIDER", value = "deepgram" },
        { name = "STT_STREAMING_PROVIDER", value = "deepgram" },
        { name = "GENERATION_PROVIDER", value = "openai" },
        { name = "EMBEDDING_PROVIDER", value = "openai" },
      ]

      # Sensitive values — injected by ECS from Secrets Manager at container
      # start, never written into this task definition in plaintext.
      # "<arn>:<json_key>::" pulls a single key out of a JSON secret.
      secrets = [
        { name = "DB_PASSWORD", valueFrom = "${aws_db_instance.reqsai.master_user_secret[0].secret_arn}:password::" },
        { name = "JWT_PRIVATE_KEY_PEM", valueFrom = "${aws_secretsmanager_secret.jwt.arn}:private_key_pem::" },
        { name = "JWT_PUBLIC_KEY_PEM", valueFrom = "${aws_secretsmanager_secret.jwt.arn}:public_key_pem::" },
        { name = "MAIL_USERNAME", valueFrom = "${aws_secretsmanager_secret.smtp.arn}:username::" },
        { name = "MAIL_PASSWORD", valueFrom = "${aws_secretsmanager_secret.smtp.arn}:password::" },
        { name = "DEEPGRAM_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai.arn}:deepgram_api_key::" },
        { name = "OPENAI_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai.arn}:openai_api_key::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.reqsai_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  lifecycle {
    # reqsai-api's deploy.yml registers a new task definition revision on
    # every push (with the freshly built image tag). Without this, the
    # next `terraform apply` would see that drift and try to revert the
    # container definition back to the ":latest" placeholder below,
    # undoing whatever CI just deployed.
    ignore_changes = [container_definitions]
  }
}
