output "resource_group_name" {
  description = "Resource group that holds every resource of the environment (deleting it deletes them all)."
  value       = azurerm_resource_group.this.name
}

output "public_ip" {
  description = "Static public IPv4 address of the VM (target of the DNS A record of the app hostname)."
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
  description = "Operator shell, through the second SSH port open to admin_cidrs."
  value       = "ssh -p ${var.admin_ssh_port} ubuntu@${local.public_ip}"
}

output "ansible_inventory" {
  description = "Ansible inventory of the host for the operator (second SSH port)."
  value = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    host_alias   = local.name
    ansible_host = local.public_ip
    ansible_port = var.admin_ssh_port
    app_hostname = local.app_hostname
  })
}
