data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = var.shape
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  # Excludes the Minimal and the x86 builds that share the OS version.
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-${replace(var.ubuntu_version, ".", "\\.")}-aarch64-"]
    regex  = true
  }
}

locals {
  dns_label           = substr(replace(lower(var.name), "/[^a-z0-9]/", ""), 0, 15)
  availability_domain = coalesce(var.availability_domain, data.oci_identity_availability_domains.this.availability_domains[0].name)
  image_id            = var.image_ocid != null ? var.image_ocid : try(data.oci_core_images.ubuntu.images[0].id, null)
  image_name          = var.image_ocid == null ? try(data.oci_core_images.ubuntu.images[0].display_name, null) : null

  # OCI security rules take IANA protocol numbers.
  protocol = {
    icmp = "1"
    tcp  = "6"
    udp  = "17"
  }

  public_ingress = {
    http  = { description = "HTTP for ACME challenges and redirect to HTTPS", protocol = local.protocol.tcp, port = 80 }
    https = { description = "HTTPS", protocol = local.protocol.tcp, port = 443 }
    http3 = { description = "HTTP/3 (QUIC)", protocol = local.protocol.udp, port = 443 }
  }

  ssh_sources = merge(
    { for cidr in var.deploy_ssh_cidrs : cidr => "SSH for automated deploys" },
    { for cidr in var.admin_cidrs : cidr => "SSH from an admin network" },
  )
}
