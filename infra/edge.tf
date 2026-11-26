# CloudFront with the default *.cloudfront.net certificate. With no custom
# domain, CloudFront pins the viewer minimum protocol to TLSv1 - an intentional
# RelixQ finding.

locals {
  cf_cache_disabled_policy_id   = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  cf_all_viewer_no_host_policy  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  cf_origin_id_payment_api      = "payment-api"
  cf_origin_payment_api_dnsname = aws_eip.host.public_dns
}

resource "aws_cloudfront_distribution" "edge" {
  enabled         = true
  comment         = "${local.name} edge for the payment API"
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"

  origin {
    origin_id   = local.cf_origin_id_payment_api
    domain_name = local.cf_origin_payment_api_dnsname

    custom_origin_config {
      http_port              = 8080
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = local.cf_origin_id_payment_api
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cf_cache_disabled_policy_id
    origin_request_policy_id = local.cf_all_viewer_no_host_policy
    compress                 = true
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
