#
# CloudFront Distributions for HTTPS without Custom Domain
#
# Enables HTTPS access using default *.cloudfront.net certificates
# when custom Route53 DNS is not available (workshops, demos, evaluations)
#
# TODO: Simplify deployment modes to avoid dual-access complexity:
#   1. CloudFront-only: Use *.cloudfront.net URLs directly (no custom domain)
#   2. Custom Domain → ALB: Traditional setup with ACM certificates
#   3. Custom Domain → CloudFront: Route53 points to CloudFront (best of both)
#
# When enable_cloudfront=true AND enable_route53_dns=true, Route53 should
# point to CloudFront distributions instead of ALBs. This eliminates the
# need to handle dual-access (same deployment accessible via both CloudFront
# and custom domain URLs), which causes OAuth2 callback_uri and session
# cookie issues due to Host header rewriting.
#

# Data sources for managed CloudFront policies
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# CloudFront distribution for MCP Gateway ALB
resource "aws_cloudfront_distribution" "mcp_gateway" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  comment             = "${var.name} MCP Gateway Registry CloudFront Distribution"
  default_root_object = ""
  price_class         = "PriceClass_100"

  origin {
    domain_name = module.mcp_gateway.alb_dns_name
    origin_id   = "mcp-gateway-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Custom header to tell backend the original protocol was HTTPS
    # Note: We use X-Forwarded-Proto directly - ALB won't overwrite origin custom headers
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }

    # Custom header to indicate this request came through CloudFront
    # The auth server will use this to check X-Forwarded-Host for the original domain
    custom_header {
      name  = "X-Cloudfront-Forwarded-Proto"
      value = "https"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "mcp-gateway-alb"

    # Disable caching for dynamic content
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    # Forward all headers to origin
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.name}-mcp-gateway-cloudfront"
      Component = "mcp-gateway"
    }
  )
}

# CloudFront distribution for Keycloak ALB
resource "aws_cloudfront_distribution" "keycloak" {
  count = var.enable_cloudfront ? 1 : 0

  enabled     = true
  comment     = "${var.name} Keycloak CloudFront Distribution"
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_lb.keycloak.dns_name
    origin_id   = "keycloak-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Custom header to tell Keycloak the original protocol was HTTPS
    # Note: We use X-Forwarded-Proto directly because Keycloak checks this header
    # The ALB will NOT overwrite this when using http-only origin protocol
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "keycloak-alb"

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.name}-keycloak-cloudfront"
      Component = "keycloak"
    }
  )
}
