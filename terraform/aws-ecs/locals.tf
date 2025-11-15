locals {
  common_tags = {
    Project     = "mcp-gateway-registry"
    Component   = "keycloak"
    Environment = "production"
    ManagedBy   = "terraform"
    CreatedAt   = timestamp()
  }
}
