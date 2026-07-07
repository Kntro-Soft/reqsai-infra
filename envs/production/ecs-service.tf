# Ties everything together: runs the task definition on Fargate, in the
# private subnets, registered behind the ALB's target group.
resource "aws_ecs_service" "reqsai_api" {
  name            = "reqsai-api"
  cluster         = aws_ecs_cluster.reqsai.id
  task_definition = aws_ecs_task_definition.reqsai_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # private subnet + NAT handles outbound; no public IP needed
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.reqsai_api.arn
    container_name   = "reqsai-api"
    container_port   = 8080
  }

  # Spring Boot + Hibernate + Flyway on 0.25 vCPU takes minutes to boot, not
  # seconds. Without this, ECS starts counting failed ALB health checks
  # immediately and kills the task mid-startup, causing an endless
  # restart loop that never gets a chance to finish booting.
  health_check_grace_period_seconds = 180

  # The ALB must exist and be able to reach the tasks before ECS starts
  # counting health checks, otherwise the service can flap on first deploy.
  depends_on = [aws_lb_listener.http]

  lifecycle {
    # reqsai-api's deploy.yml now updates the running service to a new task
    # definition revision on every push. Without this, `terraform apply`
    # would see that drift and roll the service back to whatever revision
    # Terraform itself last created.
    ignore_changes = [task_definition]
  }
}
