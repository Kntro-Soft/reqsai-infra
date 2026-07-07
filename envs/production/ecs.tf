# The cluster itself is free — you only pay for the Fargate tasks that run
# inside it (added in a later step, once the ALB and RDS pieces exist).
resource "aws_ecs_cluster" "reqsai" {
  name = "reqsai-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "disabled" # extra CloudWatch metrics cost money; enable later if needed
  }
}

# Where reqsai-api's application logs (stdout/stderr) go once it's running
# as an ECS task. 14 days is enough to debug recent issues without paying
# to store logs indefinitely.
resource "aws_cloudwatch_log_group" "reqsai_api" {
  name              = "/ecs/reqsai-${var.environment}/reqsai-api"
  retention_in_days = 14
}
