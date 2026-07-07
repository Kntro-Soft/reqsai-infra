variable "aws_region" {
  description = "AWS region where the Terraform state bucket and lock table are created."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that stores Terraform state for all other reqsai-infra configurations. Must be globally unique across all AWS accounts."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used to lock Terraform state during apply, preventing concurrent runs from corrupting it."
  type        = string
  default     = "reqsai-terraform-locks"
}
