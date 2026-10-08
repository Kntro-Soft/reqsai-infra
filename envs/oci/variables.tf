variable "region" {
  description = "OCI region identifier. Always Free compute only exists in the tenancy home region (e.g. sa-santiago-1, sa-saopaulo-1)."
  type        = string
}

variable "oci_config_profile" {
  description = "Profile of ~/.oci/config (API signing key) the provider authenticates with."
  type        = string
  default     = "DEFAULT"
}

variable "tenancy_ocid" {
  description = "OCID of the tenancy (used to list availability domains)."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment for ReqsAI (create one, e.g. 'reqsai', so it stays apart from other projects in the tenancy)."
  type        = string
}

variable "environment" {
  description = "Environment name, used in display names (reqsai-<environment>) and in the Environment tag."
  type        = string
  default     = "mvp"
}

variable "availability_domain" {
  description = "Availability domain name. Null picks the first one; try another when the region reports 'Out of host capacity' for A1."
  type        = string
  default     = null
}

variable "vcn_cidr" {
  description = "CIDR block of the dedicated VCN."
  type        = string
  default     = "10.30.0.0/16"
}

variable "ocpus" {
  description = "OCPUs of the VM.Standard.A1.Flex instance. The tenancy-wide Always Free A1 allowance is shared with any other A1 instance (e.g. another project's VM)."
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory in GB of the VM.Standard.A1.Flex instance. 6 or more selects the 'medium' Ansible memory profile."
  type        = number
  default     = 6
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB (the Always Free block storage allowance is shared by all boot and block volumes of the tenancy)."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_in_gbs >= 50
    error_message = "boot_volume_size_in_gbs must be at least 50 (the platform image minimum is ~47 GB)."
  }
}

variable "preserve_boot_volume" {
  description = "Keep the boot volume, and the database on it, if the instance is destroyed or replaced."
  type        = bool
  default     = true
}

variable "image_ocid" {
  description = "Explicit image OCID. Null resolves the newest Canonical Ubuntu 24.04 aarch64 platform image."
  type        = string
  default     = null
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed for the 'ubuntu' user. Ansible connects with the matching private key."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to reach SSH (port 22). Empty closes port 22 entirely."
  type        = list(string)
  default     = []
}

variable "deploy_ssh_cidrs" {
  description = "Extra CIDR blocks allowed to reach SSH for the GitHub Actions deploy (GitHub-hosted runners have no fixed IP; see docs/oci-migration.md before widening this)."
  type        = list(string)
  default     = []
}

variable "reserve_public_ip" {
  description = "Use a reserved public IP (kept if the instance is replaced) instead of an ephemeral one."
  type        = bool
  default     = true
}

variable "app_hostname" {
  description = "Public hostname Caddy serves (e.g. reqsai.tech). Empty serves <public-ip-with-dashes>.sslip.io, useful before the DNS cutover."
  type        = string
  default     = ""
}
