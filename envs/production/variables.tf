variable "aws_region" {
  description = "AWS region for all production resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the production VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "frontend_url" {
  description = "Base URL of the deployed reqsai-web SPA. Update this once the frontend (S3+CloudFront) exists — used to build links in emails (verify-email, invitations, etc.)."
  type        = string
  default     = "https://TODO-set-frontend-url-once-deployed.example.com"
}

variable "image_tag" {
  description = "Tag of the reqsai-api image in ECR to deploy. ECR tags are immutable, so each new build needs a new tag (e.g. the git short SHA) — update this and re-apply to roll out a manually-built image. Once CI (deploy.yml) owns deployments, this stops being used (task definition updates go through ECS directly, outside Terraform)."
  type        = string
}
