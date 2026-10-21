resource "azurerm_linux_virtual_machine" "app" {
  name                = local.name
  computer_name       = local.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.vm_size
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.app.id]

  admin_username                  = "ubuntu"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "ubuntu"
    public_key = trimspace(var.admin_ssh_public_key)
  }

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    deploy_ssh_public_key = trimspace(var.deploy_ssh_public_key)
    admin_ssh_port        = var.admin_ssh_port
  }))

  os_disk {
    name                 = "${local.name}-os"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  # Trusted Launch (Secure Boot, vTPM) is not offered on the Arm64 B-series v2 sizes.

  boot_diagnostics {}

  lifecycle {
    # A cloud-init change must not replace the host and its database.
    ignore_changes = [custom_data]
  }
}
