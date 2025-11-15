# Networking resources for MCP Gateway Registry

# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "mcp" {
  name        = "${local.name_prefix}.local"
  description = "Service discovery namespace for MCP Gateway Registry"
  vpc         = var.vpc_id
  tags        = local.common_tags
}

# Main Application Load Balancer (for registry, auth, gradio)
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = var.alb_scheme == "internal"
  enable_deletion_protection = false

  vpc_id  = var.vpc_id
  subnets = var.alb_scheme == "internal" ? var.private_subnet_ids : var.public_subnet_ids

  # Security Groups
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = var.ingress_cidr_blocks[0]
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = var.ingress_cidr_blocks[0]
    }
    auth_port = {
      from_port   = 8888
      to_port     = 8888
      ip_protocol = "tcp"
      cidr_ipv4   = var.ingress_cidr_blocks[0]
    }
    gradio_port = {
      from_port   = 7860
      to_port     = 7860
      ip_protocol = "tcp"
      cidr_ipv4   = var.ingress_cidr_blocks[0]
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = merge(
    {
      http = {
        port     = 80
        protocol = "HTTP"
        forward = {
          target_group_key = "registry"
        }
      }
      auth = {
        port     = 8888
        protocol = "HTTP"
        forward = {
          target_group_key = "auth"
        }
      }
      gradio = {
        port     = 7860
        protocol = "HTTP"
        forward = {
          target_group_key = "gradio"
        }
      }
    },
    var.certificate_arn != "" ? {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = var.certificate_arn
        forward = {
          target_group_key = "registry"
        }
      }
    } : {}
  )

  target_groups = {
    registry = {
      backend_protocol                  = "HTTP"
      backend_port                      = 80
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
    auth = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8888
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
    gradio = {
      backend_protocol                  = "HTTP"
      backend_port                      = 7860
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
  }

  tags = local.common_tags
}

# Keycloak ALB (can be internal or internet-facing)
module "keycloak_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${local.name_prefix}-kc-alb"
  load_balancer_type = "application"
  internal           = var.keycloak_alb_scheme == "internal"
  enable_deletion_protection = false

  vpc_id  = var.vpc_id
  subnets = var.keycloak_alb_scheme == "internal" ? var.private_subnet_ids : var.public_subnet_ids

  # Security Groups - Allow access from specified CIDRs
  security_group_ingress_rules = {
    keycloak_port_primary = {
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      cidr_ipv4   = var.keycloak_ingress_cidr
    }
    keycloak_port_ec2 = {
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      cidr_ipv4   = var.keycloak_ingress_cidr_ec2
    }
    keycloak_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTPS access to Keycloak ALB"
    }
    keycloak_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP access to Keycloak ALB (redirect to HTTPS)"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = {
    keycloak_http_8080 = {
      port     = 8080
      protocol = "HTTP"
      forward = {
        target_group_key = "keycloak"
      }
    }
  }

  # HTTPS listeners are only created if keycloak_certificate_arn is provided
  # The aws_lb_listener resource will handle the conditional creation


  target_groups = {
    keycloak = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8080
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 60
        matcher             = "200"
        path                = "/health/ready"
        port                = 9000
        protocol            = "HTTP"
        timeout             = 10
        unhealthy_threshold = 3
      }

      create_attachment = false
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Keycloak Authentication"
  })
}

# HTTPS listener for Keycloak ALB (created only if certificate is provided)
resource "aws_lb_listener" "keycloak_https" {
  count = var.keycloak_certificate_arn != "" ? 1 : 0

  load_balancer_arn = module.keycloak_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.keycloak_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = module.keycloak_alb.target_groups["keycloak"].arn
  }
}

# HTTP to HTTPS redirect listener for Keycloak ALB (created only if certificate is provided)
resource "aws_lb_listener" "keycloak_http_redirect" {
  count = var.keycloak_certificate_arn != "" ? 1 : 0

  load_balancer_arn = module.keycloak_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
