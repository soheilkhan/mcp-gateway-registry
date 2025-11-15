#!/bin/bash
# Temporarily disable Keycloak strict hostname to allow admin console access

set -e

echo "This will restart the Keycloak service with less strict hostname settings."
echo "This allows admin console access during initial configuration."
echo ""
echo "To apply this change, you need to:"
echo "1. Update terraform.tfvars or variables to set KC_HOSTNAME_STRICT=false"
echo "2. Run: terraform apply"
echo ""
echo "Alternatively, you can restart the ECS task with updated environment variables."
echo ""
echo "Would you like me to show you the current Keycloak environment variables? (y/n)"
