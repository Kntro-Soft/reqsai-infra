resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "${local.name}-app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 0)]
}

locals {
  # Caddy on 80/TCP (ACME HTTP-01 and the redirect), 443/TCP and 443/UDP (HTTP/3), and SSH on admin_ssh_port
  # for the operator. SSH on 22 is not open: each deploy run adds a rule for its runner's address and removes it
  # (deploy-mvp.yml, with the identity of github-deploy.tf).
  inbound_rules = {
    http      = { priority = 100, protocol = "Tcp", port = "80", sources = ["0.0.0.0/0"] }
    https     = { priority = 110, protocol = "Tcp", port = "443", sources = ["0.0.0.0/0"] }
    http3     = { priority = 120, protocol = "Udp", port = "443", sources = ["0.0.0.0/0"] }
    admin_ssh = { priority = 140, protocol = "Tcp", port = tostring(var.admin_ssh_port), sources = var.admin_cidrs }
  }
}

resource "azurerm_network_security_group" "app" {
  name                = "${local.name}-app"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.inbound_rules

    content {
      name                       = "allow-${replace(security_rule.key, "_", "-")}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefixes    = security_rule.value.sources
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_public_ip" "app" {
  name                = "${local.name}-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  allocation_method   = "Static"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_network_interface" "app" {
  name                = "${local.name}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }
}
