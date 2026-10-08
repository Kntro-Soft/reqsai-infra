variable "name" {
  description = "Prefix for every resource display name (e.g. reqsai-mvp)."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment that holds every resource of this host."
  type        = string
}

variable "tenancy_ocid" {
  description = "OCID of the tenancy, used to list the availability domains."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain name (e.g. 'Uocm:SA-SANTIAGO-1-AD-1'). Null picks the first one of the region; try another one when A1 capacity is exhausted."
  type        = string
  default     = null
}

variable "vcn_cidr" {
  description = "CIDR block of the dedicated VCN. Only one /24 public subnet is carved out of it."
  type        = string
  default     = "10.30.0.0/16"
}

variable "shape" {
  description = "Compute shape. VM.Standard.A1.Flex (Ampere, arm64) is the one covered by the Always Free allowance."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "OCPUs of the flexible shape."
  type        = number
  default     = 1

  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 4
    error_message = "ocpus must be between 1 and 4."
  }
}

variable "memory_in_gbs" {
  description = "Memory of the flexible shape, in GB."
  type        = number
  default     = 6

  validation {
    condition     = var.memory_in_gbs >= 1 && var.memory_in_gbs <= 24
    error_message = "memory_in_gbs must be between 1 and 24."
  }
}

variable "ubuntu_version" {
  description = "Canonical Ubuntu release of the platform image."
  type        = string
  default     = "24.04"
}

variable "image_ocid" {
  description = "Explicit image OCID. Null resolves the newest Canonical Ubuntu <ubuntu_version> aarch64 platform image compatible with the shape."
  type        = string
  default     = null
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB. It holds the OS, Docker images, the Postgres volume and the local backups."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_in_gbs >= 50
    error_message = "boot_volume_size_in_gbs must be at least 50."
  }
}

variable "preserve_boot_volume" {
  description = "Keep the boot volume (and the database on it) when the instance is destroyed or replaced."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key (one line) installed for the 'ubuntu' user."
  type        = string
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to reach SSH (port 22)."
  type        = list(string)
  default     = []
}

variable "deploy_ssh_cidrs" {
  description = "Extra CIDR blocks allowed to reach SSH for automated deploys (e.g. GitHub-hosted runners). Kept apart from admin_cidrs so it can be reviewed on its own."
  type        = list(string)
  default     = []
}

variable "reserve_public_ip" {
  description = "Attach a reserved public IP, which survives instance replacement. False uses an ephemeral public IP, which is released when the instance is terminated."
  type        = bool
  default     = true
}

variable "freeform_tags" {
  description = "Free-form tags applied to every resource."
  type        = map(string)
  default     = {}
}
