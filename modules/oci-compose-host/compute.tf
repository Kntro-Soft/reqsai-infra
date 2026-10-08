resource "oci_core_instance" "app" {
  compartment_id       = var.compartment_ocid
  availability_domain  = local.availability_domain
  display_name         = var.name
  shape                = var.shape
  preserve_boot_volume = var.preserve_boot_volume
  freeform_tags        = var.freeform_tags

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = tostring(!var.reserve_public_ip)
    hostname_label   = "app"
    nsg_ids          = [oci_core_network_security_group.app.id]
    display_name     = var.name
  }

  metadata = {
    ssh_authorized_keys = trimspace(var.ssh_public_key)
    user_data           = base64encode(file("${path.module}/templates/cloud-init.yaml"))
  }

  # Only the IMDSv2 endpoints (/opc/v2, with the Authorization header).
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }

  lifecycle {
    precondition {
      condition     = local.image_id != null
      error_message = "No Canonical Ubuntu ${var.ubuntu_version} aarch64 image matches ${var.shape} in this region; set image_ocid."
    }

    # A newer platform image, new keys or new cloud-init must not replace the host
    # that holds the database. Extra SSH keys are managed by Ansible
    # (base_authorized_keys).
    ignore_changes = [source_details[0].source_id, metadata, defined_tags]
  }
}

data "oci_core_vnic_attachments" "app" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.app.id
}

data "oci_core_private_ips" "app" {
  vnic_id = data.oci_core_vnic_attachments.app.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "app" {
  count = var.reserve_public_ip ? 1 : 0

  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = var.name
  private_ip_id  = data.oci_core_private_ips.app.private_ips[0].id
  freeform_tags  = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
