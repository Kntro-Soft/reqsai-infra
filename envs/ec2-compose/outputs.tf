output "instance_id" {
  description = "EC2 instance id (target for SSM Session Manager)."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP attached to the instance."
  value       = aws_eip.app.public_ip
}

output "app_hostname" {
  description = "Hostname Caddy requests a Let's Encrypt certificate for."
  value       = local.app_hostname
}

output "app_url" {
  description = "Public HTTPS URL of the application."
  value       = "https://${local.app_hostname}"
}

output "ssh_command" {
  description = "Interactive shell on the host (direct SSH when admin_cidrs is set, SSH tunnelled through SSM otherwise)."
  value = local.use_ssm_transport ? join(" ", [
    "ssh -o ProxyCommand=\"aws ssm start-session --region ${var.aws_region} --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p\"",
    "ubuntu@${aws_instance.app.id}",
  ]) : "ssh ubuntu@${aws_eip.app.public_ip}"
}

output "ssm_session_command" {
  description = "Shell through SSM Session Manager, no SSH key or open port needed."
  value       = var.enable_ssm ? "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.app.id}" : null
}

output "backup_s3_bucket" {
  description = "S3 bucket for off-host database dumps (empty when enable_backup_bucket is false)."
  value       = var.enable_backup_bucket ? aws_s3_bucket.backups[0].id : ""
}

output "memory_profile" {
  description = "Memory profile Ansible applies, derived from the instance memory (small >= 2 GiB, micro otherwise)."
  value       = local.memory_profile
}

output "instance_architecture" {
  description = "CPU architecture of the instance; container images must be built for linux/<this>."
  value       = local.ami_architecture
}

output "instance_free_tier_eligible" {
  description = "Whether AWS flags instance_type as Free Tier eligible for this account."
  value       = data.aws_ec2_instance_type.selected.free_tier_eligible
}

output "ansible_inventory" {
  description = "Ansible inventory for this host; write it with: terraform output -raw ansible_inventory > ../../ansible/inventory/hosts.yml"
  value = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    host_alias       = local.name
    ansible_host     = local.use_ssm_transport ? aws_instance.app.id : aws_eip.app.public_ip
    use_ssm          = local.use_ssm_transport
    app_hostname     = local.app_hostname
    aws_region       = var.aws_region
    memory_profile   = local.memory_profile
    backup_s3_bucket = var.enable_backup_bucket ? aws_s3_bucket.backups[0].id : ""
    ecr_registry     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  })
}

output "github_deploy_role_arn" {
  description = "IAM role the GitHub deploy workflow assumes (AWS_DEPLOY_ROLE_ARN in the mvp environment)."
  value       = one(aws_iam_role.github_deploy[*].arn)
}
