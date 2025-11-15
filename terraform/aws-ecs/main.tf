# MCP Gateway Registry - AWS ECS Deployment
# This Terraform configuration deploys the MCP Gateway to AWS ECS Fargate

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# MCP Gateway Module
module "mcp_gateway" {
  source = "./modules/mcp-gateway"

  # Basic configuration
  name = var.name

  # Network configuration
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  # ECS configuration
  ecs_cluster_arn         = module.ecs_cluster.arn
  ecs_cluster_name        = module.ecs_cluster.name
  task_execution_role_arn = module.ecs_cluster.task_exec_iam_role_arn

  # Keycloak configuration
  postgres_version      = "15.7"

  # HTTPS configuration
  certificate_arn            = var.certificate_arn
  keycloak_certificate_arn   = var.keycloak_certificate_arn

  # Auto-scaling configuration
  enable_autoscaling        = true
  autoscaling_min_capacity  = 2
  autoscaling_max_capacity  = 4
  autoscaling_target_cpu    = 70
  autoscaling_target_memory = 80

  # Monitoring configuration
  enable_monitoring = var.enable_monitoring
  alarm_email       = var.alarm_email

  # Keycloak OAuth2 secrets
  keycloak_client_secret     = var.keycloak_client_secret
  keycloak_m2m_client_secret = var.keycloak_m2m_client_secret

  # Keycloak ALB configuration
  keycloak_alb_scheme        = var.keycloak_alb_scheme
  keycloak_ingress_cidr      = var.keycloak_ingress_cidr
  keycloak_ingress_cidr_ec2  = var.keycloak_ingress_cidr_ec2
}
