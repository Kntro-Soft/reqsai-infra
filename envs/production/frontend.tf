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

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest tier: US + Canada + Europe edge locations only

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # AWS managed "CachingOptimized" policy — long cache, gzip/brotli aware.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
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

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # No custom domain yet — CloudFront's own *.cloudfront.net cert, HTTPS
    # included at no extra cost. Switch to an ACM cert + custom domain later.
    cloudfront_default_certificate = true
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
