# AWS-side authority for tamci.app. Nameservers (output dns_nameservers)
# must be set at the registrar (name.com) — that one step is manual,
# everything else (records, certs) is Terraform-managed from here on.
resource "aws_route53_zone" "root" {
  name = "tamci.app"
}
