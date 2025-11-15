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
  description = "ARN of ACM certificate for HTTPS (optional, creates HTTP-only if not provided)"
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

#
# Keycloak Configuration Variables
#

variable "keycloak_domain" {
  description = "Full domain for Keycloak (e.g., kc.example.com)"
  type        = string
}

variable "root_domain" {
  description = "Root domain with Route53 hosted zone"
  type        = string
}

variable "keycloak_admin" {
  description = "Keycloak admin username"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "keycloak_database_username" {
  description = "Keycloak database username"
  type        = string
  sensitive   = true
  default     = "keycloak"
}

variable "keycloak_database_password" {
  description = "Keycloak database password"
  type        = string
  sensitive   = true
}

variable "keycloak_database_min_acu" {
  description = "Minimum Aurora Capacity Units"
  type        = number
  default     = 0.5
}

variable "keycloak_database_max_acu" {
  description = "Maximum Aurora Capacity Units"
  type        = number
  default     = 2
}

variable "keycloak_log_level" {
  description = "Keycloak log level"
  type        = string
  default     = "INFO"
}

