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
