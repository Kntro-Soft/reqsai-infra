# 1 vCPU / 2 GB — the realistic minimum for a Spring Boot web app on
# Fargate (0.25/0.5 caused CPU throttling severe enough that the app never
# finished booting before the ALB health check killed the task). Fargate
# cpu/memory are in specific paired units: "1024" = 1 vCPU, "2048" = 2 GB.
resource "aws_ecs_task_definition" "reqsai_api" {
  family                   = "reqsai-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required by Fargate: each task gets its own ENI/IP
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # Explicit instead of relying on Fargate's implicit default, to rule out
  # any ambiguity while debugging the "no descriptor matching platform"
  # image pull error.
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "reqsai-api"
      image     = "${aws_ecr_repository.reqsai_api.repository_url}:${var.image_tag}"
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
        { name = "FRONTEND_URL", value = "https://${aws_cloudfront_distribution.web.domain_name}" },
        # Without this, the browser blocks the deployed frontend's calls to
        # the API under CORS (default is http://localhost:4200, dev only).
        # WS_ALLOWED_ORIGINS inherits this same value unless set separately
        # (application.yml: ${WS_ALLOWED_ORIGINS:${CORS_ALLOWED_ORIGINS:...}}).
        { name = "CORS_ALLOWED_ORIGINS", value = "https://${aws_cloudfront_distribution.web.domain_name}" },
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
        # Spring AI's own autoconfiguration selectors (distinct from
        # GENERATION_PROVIDER/EMBEDDING_PROVIDER above, which only control
        # this app's internal routing). Without them, spring.ai.model.chat
        # defaults to "none" but Spring AI still tried to instantiate the
        # Google GenAI client present on the classpath and failed for lack
        # of a Gemini API key — this selects OpenAI explicitly instead.
        { name = "SPRING_AI_MODEL_CHAT", value = "openai" },
        { name = "SPRING_AI_MODEL_EMBEDDING", value = "openai" },
        { name = "SPRINGDOC_API_DOCS_ENABLED", value = "true" },
        { name = "SPRINGDOC_SWAGGER_UI_ENABLED", value = "true" },
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
    # reqsai-api's deploy.yml (now wired up, see ecs/task-definition.json
    # in that repo) registers a new revision on every push with the fresh
    # image tag. Without this, the next `terraform apply` would see that
    # drift and try to revert the container definition back to whatever
    # var.image_tag was last set to here, undoing CI's deployment.
    ignore_changes = [container_definitions]
  }
}
