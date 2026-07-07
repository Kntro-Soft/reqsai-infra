output "state_bucket_name" {
  description = "S3 bucket name to reference in every other configuration's backend \"s3\" block."
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table name to reference in every other configuration's backend \"s3\" block."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_account_id" {
  description = "AWS account id these resources were created in, for reference."
  value       = data.aws_caller_identity.current.account_id
}
