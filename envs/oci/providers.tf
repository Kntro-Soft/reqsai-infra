# No backend block: state is local (terraform.tfstate, ignored by git) unless you
# opt into the S3-compatible backend described in backend.hcl.example.
provider "oci" {
  region              = var.region
  config_file_profile = var.oci_config_profile
}
