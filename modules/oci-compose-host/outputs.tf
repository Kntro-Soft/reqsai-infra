output "instance_id" {
  description = "OCID of the instance."
  value       = oci_core_instance.app.id
}

output "public_ip" {
  description = "Public IPv4 of the instance (reserved when reserve_public_ip is true, ephemeral otherwise)."
  value       = var.reserve_public_ip ? oci_core_public_ip.app[0].ip_address : oci_core_instance.app.public_ip
}

output "private_ip" {
  description = "Private IPv4 of the instance inside the VCN."
  value       = oci_core_instance.app.private_ip
}

output "availability_domain" {
  description = "Availability domain the instance runs in."
  value       = oci_core_instance.app.availability_domain
}

output "image_id" {
  description = "Image the instance was created from."
  value       = local.image_id
}

output "image_name" {
  description = "Display name of the resolved platform image (null when image_ocid is set)."
  value       = local.image_name
}

output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.this.id
}

output "network_security_group_id" {
  description = "OCID of the network security group attached to the instance VNIC."
  value       = oci_core_network_security_group.app.id
}
