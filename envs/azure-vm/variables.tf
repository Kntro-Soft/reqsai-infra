variable "subscription_id" {
  description = "Azure subscription that holds the environment."
  type        = string
}

variable "location" {
  description = "Azure region. Azure for Students only allows a few regions; the ARM B-series v2 sizes are offered in northcentralus and westus among them."
  type        = string
  default     = "northcentralus"
}

variable "environment" {
  description = "Environment name, used in resource names (reqsai-<environment>-*) and in the Environment tag."
  type        = string
  default     = "mvp"
}

variable "vm_size" {
  description = "VM size. The application images are linux/arm64, so it must be an Arm64 size (a 'p' among its feature letters)."
  type        = string
  default     = "Standard_B2pls_v2"

  validation {
    condition     = can(regex("^Standard_[A-Z]+[0-9]+[a-z]*p[a-z]*_v[0-9]+$", var.vm_size))
    error_message = "vm_size must be an Arm64 size (e.g. Standard_B2pls_v2): the application images are linux/arm64."
  }
}

variable "os_disk_size_gb" {
  description = "Size in GiB of the OS disk, which also holds Docker images, the Postgres volume and the local backups."
  type        = number
  default     = 32
}

variable "os_disk_storage_account_type" {
  description = "Managed disk type of the OS disk."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "vnet_cidr" {
  description = "Address space of the dedicated virtual network; one /24 subnet is carved out of it."
  type        = string
  default     = "10.30.0.0/16"
}

variable "admin_cidrs" {
  description = "Addresses allowed on the operator SSH port (admin_ssh_port), which exists because the operator's network only lets out 80, 443, 8080 and 993."
  type        = list(string)
}

variable "admin_ssh_port" {
  description = "Second port sshd listens on, open only to admin_cidrs."
  type        = number
  default     = 8080
}

variable "admin_ssh_public_key" {
  description = "Public key of the operator (user ubuntu)."
  type        = string
}

variable "deploy_ssh_public_key" {
  description = "Public key whose private half is the GitHub secret DEPLOY_SSH_PRIVATE_KEY of the environment mvp."
  type        = string
}

variable "app_hostname" {
  description = "Hostname Caddy requests a Let's Encrypt certificate for. Empty uses <ip>.sslip.io, handy before the DNS points here."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}

variable "github_owner" {
  description = "GitHub organization of the repository whose deploy jobs may use the Azure identity."
  type        = string
  default     = "Kntro-Soft"
}

variable "github_repository_name" {
  description = "Repository whose deploy jobs may use the Azure identity."
  type        = string
  default     = "reqsai-infra"
}

variable "github_environment" {
  description = "GitHub environment of those deploy jobs (the OIDC subject is repo:<owner>/<repo>:environment:<this>)."
  type        = string
  default     = "mvp"
}
