# AWS-side authority for reqsai.tech. Nameservers (output ns_zone_nameservers)
# must be set at the registrar (Tech Domains) — that one step is manual,
# everything else (records, certs) is Terraform-managed from here on.
resource "aws_route53_zone" "root" {
  name = "reqsai.tech"
}
