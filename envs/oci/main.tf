locals {
  name           = "reqsai-${var.environment}"
  public_ip      = module.host.public_ip
  sslip_hostname = "${replace(local.public_ip, ".", "-")}.sslip.io"
  app_hostname   = var.app_hostname != "" ? var.app_hostname : local.sslip_hostname
  memory_profile = var.memory_in_gbs >= 6 ? "medium" : (var.memory_in_gbs >= 2 ? "small" : "micro")
}

module "host" {
  source = "../../modules/oci-compose-host"

  name                    = local.name
  tenancy_ocid            = var.tenancy_ocid
  compartment_ocid        = var.compartment_ocid
  availability_domain     = var.availability_domain
  vcn_cidr                = var.vcn_cidr
  ocpus                   = var.ocpus
  memory_in_gbs           = var.memory_in_gbs
  boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  preserve_boot_volume    = var.preserve_boot_volume
  image_ocid              = var.image_ocid
  ssh_public_key          = file(pathexpand(var.ssh_public_key_path))
  admin_cidrs             = var.admin_cidrs
  deploy_ssh_cidrs        = var.deploy_ssh_cidrs
  reserve_public_ip       = var.reserve_public_ip

  freeform_tags = {
    Project     = "reqsai"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}
