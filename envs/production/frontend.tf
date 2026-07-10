# Static hosting for reqsai-web (Angular SPA). No servers, no NAT/ALB
# involved — CloudFront serves the built assets straight from a private S3
# bucket. reqsai-web's own deploy.yml already targets this exact shape
# (S3 sync + CloudFront invalidation), it just needs the bucket/distribution
# to exist.

resource "aws_s3_bucket" "web" {
  bucket = "reqsai-web-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Required for CloudFront's Origin Access Control model: the bucket owner
# (this account) owns every object, no ACLs involved at all.
resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Lets CloudFront authenticate to the private bucket without the bucket
# ever being publicly readable — the modern replacement for the older
# "Origin Access Identity" approach.
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "reqsai-${var.environment}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Blocks direct access via the default *.cloudfront.net domain — the
# equivalent, at the CloudFront layer, of the ALB's security-group lockdown
# to CloudFront-only traffic (there's no security group for CloudFront
# itself, since it isn't in a VPC).
resource "aws_cloudfront_function" "block_default_domain" {
  name    = "reqsai-${var.environment}-block-default-domain"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/cloudfront-functions/block-default-domain.js")
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest tier: US + Canada + Europe edge locations only

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  # reqsai-web's Angular code calls relative /api and /ws paths (mirroring
  # its own dev proxy.conf.js) instead of reading environment.apiUrl. Rather
  # than changing that app, CloudFront fronts the backend under the same
  # origin so those relative calls land on the real API — same shape as the
  # dev proxy, just at the CDN layer.
  origin {
    # Must be api.tamci.app, not the raw ALB DNS name: CloudFront uses this
    # value as the TLS SNI hostname when connecting to the origin, and the
    # ALB's HTTPS listener only has a certificate for api.tamci.app — SNI
    # for the raw *.elb.amazonaws.com name matches no certificate, so the
    # TLS handshake fails and CloudFront returns 502.
    domain_name = aws_route53_record.api.name
    origin_id   = "alb-backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only" # ALB now has a real cert (api.tamci.app)
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # AWS managed "CachingOptimized" policy — long cache, gzip/brotli aware.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.block_default_domain.arn
    }
  }

  # API calls — never cached, all methods, every header/cookie/query string
  # forwarded through untouched (AWS managed "AllViewer" origin request
  # policy) so auth headers and JSON bodies reach the backend intact.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-backend"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.block_default_domain.arn
    }
  }

  # WebSocket (STOMP) handshake and traffic — same treatment as /api/*.
  ordered_cache_behavior {
    path_pattern             = "/ws/*"
    target_origin_id         = "alb-backend"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.block_default_domain.arn
    }
  }

  # SPA client-side routing: any path not found as a literal S3 object
  # (e.g. /projects/123) must still serve index.html so Angular's router
  # can take over, mirroring the try_files fallback in reqsai-web's own
  # nginx.conf (used for local/self-hosted runs, not this deployment).
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  aliases = ["app.tamci.app"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.web.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_iam_policy_document" "web_bucket_policy" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket_policy.json
}
