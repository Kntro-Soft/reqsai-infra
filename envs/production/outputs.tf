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
