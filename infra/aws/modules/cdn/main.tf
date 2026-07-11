# CloudFront in front of the ui-static S3 bucket, using Origin Access
# Control (OAC) so the bucket itself stays fully private (matches the
# public-access-block already set in the storage module). No custom
# domain/ACM cert — the default *.cloudfront.net domain is fine for a
# simple UI; add a domain/cert later if needed.

resource "aws_cloudfront_origin_access_control" "ui" {
  name                              = "${var.project}-${var.env}-ui-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "ui" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest tier — NA/EU edge locations only

  origin {
    domain_name              = var.ui_static_bucket_regional_domain_name
    origin_id                = "ui-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.ui.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ui-static"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "ui_static_cloudfront_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.ui_static_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.ui.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "ui_static_cloudfront_read" {
  bucket = var.ui_static_bucket_name
  policy = data.aws_iam_policy_document.ui_static_cloudfront_read.json
}
