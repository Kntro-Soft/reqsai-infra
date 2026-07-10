# AWS-side authority for tamci.app. Nameservers (output dns_nameservers)
# must be set at the registrar (name.com) — that one step is manual,
# everything else (records, certs) is Terraform-managed from here on.
resource "aws_route53_zone" "root" {
  name = "tamci.app"
}

# ALIAS records: free, and resolve straight to the AWS resource's current
# address without an extra DNS hop (unlike a CNAME).
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.root.zone_id
  name    = "api.tamci.app"
  type    = "A"

  alias {
    name                   = aws_lb.reqsai_api.dns_name
    zone_id                = aws_lb.reqsai_api.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.root.zone_id
  name    = "app.tamci.app"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.web.domain_name
    zone_id                = aws_cloudfront_distribution.web.hosted_zone_id
    evaluate_target_health = false
  }
}
