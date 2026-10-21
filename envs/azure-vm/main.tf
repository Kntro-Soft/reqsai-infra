# The ReqsAI MVP on one Azure VM, the same shape as envs/ec2-compose: Docker Compose runs the API, the web,
# Caddy and Postgres (pgvector) on the host; Ansible (ansible/site.yml) provisions it and deploys releases.

locals {
  name = "reqsai-${var.environment}"

  tags = merge({
    Project     = "reqsai"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "Kntro-Soft/reqsai-infra"
  }, var.tags)

  public_ip      = azurerm_public_ip.app.ip_address
  sslip_hostname = "${replace(local.public_ip, ".", "-")}.sslip.io"
  app_hostname   = var.app_hostname != "" ? var.app_hostname : local.sslip_hostname
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}
