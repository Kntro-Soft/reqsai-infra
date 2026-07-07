data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# The execution role is used BY ECS ITSELF (not your app) to pull the image
# from ECR, write logs to CloudWatch, and read the secrets referenced in the
# task definition so it can inject them as env vars before your app starts.
resource "aws_iam_role" "ecs_task_execution" {
  name               = "reqsai-${var.environment}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.jwt.arn,
      aws_secretsmanager_secret.smtp.arn,
      aws_secretsmanager_secret.ai.arn,
      aws_db_instance.reqsai.master_user_secret[0].secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name   = "read-app-secrets"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets.json
}

# The task role is assumed BY YOUR APP CODE at runtime, for any AWS API
# calls it makes directly. reqsai-api doesn't call AWS APIs today (Gemini/
# OpenAI/Deepgram are plain HTTPS, email is SMTP, not SES) — left empty on
# purpose. Attach policies here later if that changes (e.g. S3 uploads).
resource "aws_iam_role" "ecs_task" {
  name               = "reqsai-${var.environment}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}
