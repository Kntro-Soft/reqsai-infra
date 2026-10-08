resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = var.name
  dns_label      = local.dns_label
  freeform_tags  = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = var.name
  enabled        = true
  freeform_tags  = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# The default security list of a new VCN allows SSH from 0.0.0.0/0. Nothing uses
# it, but it is emptied so it cannot open port 22 by accident.
resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "${var.name}-default-unused"
  freeform_tags              = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# Subnet-level rules: all egress, plus the ICMP messages OCI recommends for path
# MTU discovery. Every application port lives in the network security group.
resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public"
  freeform_tags  = var.freeform_tags

  egress_security_rules {
    description = "Image pulls, OS updates, AI/SMTP/Stripe APIs, object storage"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    description = "Path MTU discovery (fragmentation needed)"
    source      = "0.0.0.0/0"
    protocol    = local.protocol.icmp

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    description = "Destination unreachable inside the VCN"
    source      = var.vcn_cidr
    protocol    = local.protocol.icmp

    icmp_options {
      type = 3
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = cidrsubnet(var.vcn_cidr, 8, 0)
  display_name               = "${var.name}-public"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  freeform_tags              = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-app"
  freeform_tags  = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group_security_rule" "public" {
  for_each = local.public_ingress

  network_security_group_id = oci_core_network_security_group.app.id
  description               = each.value.description
  direction                 = "INGRESS"
  protocol                  = each.value.protocol
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  dynamic "tcp_options" {
    for_each = each.value.protocol == local.protocol.tcp ? [each.value.port] : []

    content {
      destination_port_range {
        min = tcp_options.value
        max = tcp_options.value
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == local.protocol.udp ? [each.value.port] : []

    content {
      destination_port_range {
        min = udp_options.value
        max = udp_options.value
      }
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  for_each = local.ssh_sources

  network_security_group_id = oci_core_network_security_group.app.id
  description               = each.value
  direction                 = "INGRESS"
  protocol                  = local.protocol.tcp
  source                    = each.key
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}
