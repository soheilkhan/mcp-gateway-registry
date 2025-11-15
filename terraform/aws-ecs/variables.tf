variable "name" {
  description = "Name of the deployment"
  type        = string
  default     = "mcp-gateway"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for main ALB (Registry, Auth Server) HTTPS (optional, creates HTTP-only if not provided)"
  type        = string
  default     = ""
}

variable "keycloak_certificate_arn" {
  description = "ARN of ACM certificate for Keycloak ALB HTTPS (optional, creates HTTP-only if not provided). Can be same as certificate_arn if using wildcard certificate"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Whether to enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "keycloak_client_secret" {
  description = "Keycloak client secret for web application OAuth2. Get this from Keycloak Admin Console > Clients > mcp-gateway-web > Credentials > Secret"
  type        = string
  default     = "change-me-to-keycloak-web-client-secret"
  sensitive   = true
}

variable "keycloak_m2m_client_secret" {
  description = "Keycloak machine-to-machine client secret for Admin API. Get this from Keycloak Admin Console > Clients > mcp-gateway-m2m > Credentials > Secret"
  type        = string
  default     = "change-me-to-keycloak-m2m-client-secret"
  sensitive   = true
}

variable "keycloak_alb_scheme" {
  description = "Scheme for Keycloak ALB (internal or internet-facing). Set to internet-facing to access from external networks"
  type        = string
  default     = "internet-facing"
  validation {
    condition     = contains(["internal", "internet-facing"], var.keycloak_alb_scheme)
    error_message = "Keycloak ALB scheme must be either 'internal' or 'internet-facing'."
  }
}

variable "keycloak_ingress_cidr" {
  description = "CIDR block allowed to access Keycloak ALB. Defaults to both laptop and EC2 instance IPs"
  type        = string
  default     = "71.114.44.148/32"
}

variable "keycloak_ingress_cidr_ec2" {
  description = "Additional CIDR block for EC2 instance to access Keycloak ALB"
  type        = string
  default     = "44.192.72.20/32"
}