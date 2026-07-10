output "vpc_id" {
  description = "ID of the production VPC, referenced by ECS/RDS/ALB resources added later."
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public subnet ids — for the ALB."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private subnet ids — for ECS Fargate tasks."
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "Database subnet ids — for RDS."
  value       = module.vpc.database_subnets
}

output "ecr_repository_url" {
  description = "Full ECR repository URL (registry + repo name), for reference. reqsai-api's deploy.yml only needs the repo name (\"reqsai-api\") as its ECR_REPOSITORY variable — the registry host is resolved separately by the ECR login step."
  value       = aws_ecr_repository.reqsai_api.repository_url
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer — where reqsai-api will be reachable once the ECS service exists (http:// only, no custom domain/TLS yet)."
  value       = aws_lb.reqsai_api.dns_name
}

output "rds_address" {
  description = "RDS endpoint host — maps to reqsai-api's DB_HOST env var."
  value       = aws_db_instance.reqsai.address
}

output "rds_port" {
  description = "RDS port — maps to reqsai-api's DB_PORT env var."
  value       = aws_db_instance.reqsai.port
}

output "rds_db_name" {
  description = "Database name — maps to reqsai-api's DB_NAME env var."
  value       = aws_db_instance.reqsai.db_name
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master password (auto-created by RDS). The ECS task definition will reference this directly instead of reading the password into Terraform state."
  value       = aws_db_instance.reqsai.master_user_secret[0].secret_arn
}

output "jwt_secret_arn" {
  description = "ARN of the empty JWT keys secret — populate with `aws secretsmanager put-secret-value` (see README)."
  value       = aws_secretsmanager_secret.jwt.arn
}

output "smtp_secret_arn" {
  description = "ARN of the empty SMTP credentials secret — populate with `aws secretsmanager put-secret-value` (see README)."
  value       = aws_secretsmanager_secret.smtp.arn
}

output "ai_secret_arn" {
  description = "ARN of the empty AI API keys secret — populate with `aws secretsmanager put-secret-value` (see README)."
  value       = aws_secretsmanager_secret.ai.arn
}

output "web_bucket_name" {
  description = "S3 bucket name — set as the S3_BUCKET value in reqsai-web's GitHub Actions variables."
  value       = aws_s3_bucket.web.id
}

output "web_cloudfront_distribution_id" {
  description = "CloudFront distribution id — set as the CLOUDFRONT_DISTRIBUTION_ID value in reqsai-web's GitHub Actions variables (used to invalidate the cache on deploy)."
  value       = aws_cloudfront_distribution.web.id
}

output "web_url" {
  description = "Public HTTPS URL of the deployed frontend."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}

output "github_actions_api_role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN in reqsai-api's GitHub Actions repo variables."
  value       = aws_iam_role.github_actions_api.arn
}

output "dns_nameservers" {
  description = "Set these 4 as tamci.app's nameservers at name.com (the registrar) — this is the one manual step, everything else is Terraform-managed."
  value       = aws_route53_zone.root.name_servers
}

output "github_actions_web_role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN in reqsai-web's GitHub Actions repo variables."
  value       = aws_iam_role.github_actions_web.arn
}
