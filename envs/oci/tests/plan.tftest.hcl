# Offline checks of the plan logic with a mocked OCI provider (no credentials or
# network needed): terraform init -backend=false && terraform test

mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [{ id = "ad1", name = "Xyzw:SA-SANTIAGO-1-AD-1", compartment_id = "ocid1.tenancy.oc1..test" }]
    }
  }

  mock_data "oci_core_images" {
    defaults = {
      images = [{ id = "ocid1.image.oc1..ubuntu", display_name = "Canonical-Ubuntu-24.04-aarch64-2026.09.30-0" }]
    }
  }

  mock_data "oci_core_vnic_attachments" {
    defaults = {
      vnic_attachments = [{ vnic_id = "ocid1.vnic.oc1..test" }]
    }
  }

  mock_data "oci_core_private_ips" {
    defaults = {
      private_ips = [{ id = "ocid1.privateip.oc1..test", ip_address = "10.30.0.10" }]
    }
  }

  mock_resource "oci_core_public_ip" {
    defaults = {
      ip_address = "203.0.113.25"
    }
  }

  mock_resource "oci_core_instance" {
    defaults = {
      public_ip  = "198.51.100.7"
      private_ip = "10.30.0.10"
    }
  }
}

variables {
  region              = "sa-santiago-1"
  tenancy_ocid        = "ocid1.tenancy.oc1..test"
  compartment_ocid    = "ocid1.compartment.oc1..test"
  ssh_public_key_path = "tests/fixtures/id_test.pub"
  admin_cidrs         = ["203.0.113.10/32"]
}

run "defaults_reserved_ip_and_medium_profile" {
  command = apply

  assert {
    condition     = output.public_ip == "203.0.113.25"
    error_message = "The reserved public IP must be the published address."
  }

  assert {
    condition     = output.app_hostname == "203-0-113-25.sslip.io"
    error_message = "An empty app_hostname must fall back to sslip.io."
  }

  assert {
    condition     = output.memory_profile == "medium"
    error_message = "6 GB must select the medium profile."
  }

  assert {
    condition     = module.host.availability_domain == "Xyzw:SA-SANTIAGO-1-AD-1"
    error_message = "Null availability_domain must pick the first one."
  }

  assert {
    condition     = strcontains(output.ansible_inventory, "ansible_connection: ssh") && strcontains(output.ansible_inventory, "ansible_host: 203.0.113.25") && strcontains(output.ansible_inventory, "memory_profile: medium")
    error_message = "The inventory must target the public IP over SSH with the medium profile."
  }

  assert {
    condition     = length(module.host.network_security_group_id) > 0
    error_message = "The NSG must exist."
  }
}

run "ephemeral_ip_custom_hostname_small" {
  command = apply

  variables {
    reserve_public_ip = false
    app_hostname      = "reqsai.tech"
    memory_in_gbs     = 4
    deploy_ssh_cidrs  = ["0.0.0.0/0", "203.0.113.10/32"]
  }

  assert {
    condition     = output.public_ip == "198.51.100.7"
    error_message = "Without a reserved IP the instance's ephemeral IP must be published."
  }

  assert {
    condition     = output.app_url == "https://reqsai.tech"
    error_message = "app_hostname must drive app_url."
  }

  assert {
    condition     = output.memory_profile == "small"
    error_message = "4 GB must select the small profile."
  }
}

run "rejects_too_small_boot_volume" {
  command = plan

  variables {
    boot_volume_size_in_gbs = 40
  }

  expect_failures = [var.boot_volume_size_in_gbs]
}
