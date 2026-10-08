output "instance_id" {
  description = "OCID of the instance."
  value       = module.host.instance_id
}

output "public_ip" {
  description = "Public IPv4 of the instance; point the A records here at the DNS cutover."
  value       = local.public_ip
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
  description = "Interactive shell on the host (requires your IP in admin_cidrs)."
  value       = "ssh ubuntu@${local.public_ip}"
}

output "availability_domain" {
  description = "Availability domain the instance runs in."
  value       = module.host.availability_domain
}

output "image_name" {
  description = "Platform image the instance was created from (null when image_ocid is set)."
  value       = module.host.image_name
}

output "memory_profile" {
  description = "Memory profile Ansible applies, derived from memory_in_gbs (medium >= 6 GB, small >= 2 GB, micro otherwise)."
  value       = local.memory_profile
}

output "instance_architecture" {
  description = "CPU architecture of the instance; container images must be built for linux/<this>."
  value       = "arm64"
}

output "ansible_inventory" {
  description = "Ansible inventory for this host; write it with: make inventory-oci"
  value = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    host_alias     = "${local.name}-oci"
    ansible_host   = local.public_ip
    app_hostname   = local.app_hostname
    memory_profile = local.memory_profile
  })
}
