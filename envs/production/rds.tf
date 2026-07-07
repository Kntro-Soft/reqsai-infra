# PostgreSQL with pgvector for reqsai-api. Not publicly reachable — only
# the ECS tasks' security group can connect (see security-groups.tf).
resource "aws_db_instance" "reqsai" {
  identifier     = "reqsai-${var.environment}"
  engine         = "postgres"
  engine_version = "16" # RDS resolves to the latest supported 16.x minor; pgvector ships as a normal extension, no parameter group needed

  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "reqsai"
  username = "reqsai_admin"

  # RDS creates and rotates the master password itself in Secrets Manager —
  # Terraform never sees or stores the plaintext password.
  manage_master_user_password = true

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az = false # single-AZ: cheaper, accepted downtime risk if the AZ fails

  # This is the real production database — protects against an accidental
  # `terraform destroy`. To actually delete it, first set this to false,
  # apply, then destroy.
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "reqsai-${var.environment}-final"

  auto_minor_version_upgrade = true
  backup_retention_period    = 7
}
