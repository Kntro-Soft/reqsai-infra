data "aws_route53_zone" "selected" {
  count = local.use_route53 ? 1 : 0

  name         = var.dns_zone_name
  private_zone = false
}

resource "aws_route53_record" "app" {
  count = local.use_route53 ? 1 : 0

  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = local.app_hostname
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}
