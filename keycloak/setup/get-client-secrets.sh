#!/bin/bash
# Script to retrieve Keycloak client secrets from a running instance
# This is useful if you've lost the secrets or need to retrieve them again

set -e

# Configuration
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-mcp-gateway-registry_keycloak_1}"
KEYCLOAK_URL="${KEYCLOAK_ADMIN_URL:-http://localhost:8080}"
REALM="${KEYCLOAK_REALM:-mcp-gateway}"
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if admin password is set
if [ -z "$ADMIN_PASS" ]; then
    echo -e "${RED}Error: KEYCLOAK_ADMIN_PASSWORD environment variable is required${NC}"
    echo "Please set it before running this script:"
    echo "export KEYCLOAK_ADMIN_PASSWORD=\"your-admin-password\""
    exit 1
fi

echo "Retrieving Keycloak client secrets..."
echo "Container: $KEYCLOAK_CONTAINER"
echo "Server: $KEYCLOAK_URL"
echo "Realm: $REALM"
echo ""

# Method 1: Using direct API calls (preferred)
echo "Method 1: Using Keycloak Admin API..."

# Get admin token
echo "Authenticating as admin..."
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASS" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Failed to authenticate. Please check your admin password.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated successfully${NC}"
echo ""

# Get web client secret
echo "Retrieving mcp-gateway-web client secret..."
WEB_CLIENT_ID=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=mcp-gateway-web" | \
    jq -r '.[0].id // empty')

if [ ! -z "$WEB_CLIENT_ID" ] && [ "$WEB_CLIENT_ID" != "null" ]; then
    WEB_SECRET=$(curl -s \
        -H "Authorization: Bearer $TOKEN" \
        "$KEYCLOAK_URL/admin/realms/$REALM/clients/$WEB_CLIENT_ID/client-secret" | \
        jq -r '.value // empty')
else
    echo -e "${YELLOW}Warning: mcp-gateway-web client not found${NC}"
fi

# Get M2M client secret
echo "Retrieving mcp-gateway-m2m client secret..."
M2M_CLIENT_ID=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=mcp-gateway-m2m" | \
    jq -r '.[0].id // empty')

if [ ! -z "$M2M_CLIENT_ID" ] && [ "$M2M_CLIENT_ID" != "null" ]; then
    M2M_SECRET=$(curl -s \
        -H "Authorization: Bearer $TOKEN" \
        "$KEYCLOAK_URL/admin/realms/$REALM/clients/$M2M_CLIENT_ID/client-secret" | \
        jq -r '.value // empty')
else
    echo -e "${YELLOW}Warning: mcp-gateway-m2m client not found${NC}"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}Keycloak Client Credentials:${NC}"
echo "=============================================="
echo "# Add these to your .env file:"
echo ""
if [ ! -z "$WEB_SECRET" ]; then
    echo "KEYCLOAK_CLIENT_ID=mcp-gateway-web"
    echo "KEYCLOAK_CLIENT_SECRET=$WEB_SECRET"
    echo ""
fi
if [ ! -z "$M2M_SECRET" ]; then
    echo "KEYCLOAK_M2M_CLIENT_ID=mcp-gateway-m2m"
    echo "KEYCLOAK_M2M_CLIENT_SECRET=$M2M_SECRET"
fi
echo "=============================================="

# Save to file
OUTPUT_FILE="retrieved-keycloak-secrets.txt"
echo "# Keycloak Client Credentials - Retrieved $(date)" > "$OUTPUT_FILE"
echo "# Add these to your .env file" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
if [ ! -z "$WEB_SECRET" ]; then
    echo "KEYCLOAK_CLIENT_ID=mcp-gateway-web" >> "$OUTPUT_FILE"
    echo "KEYCLOAK_CLIENT_SECRET=$WEB_SECRET" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi
if [ ! -z "$M2M_SECRET" ]; then
    echo "KEYCLOAK_M2M_CLIENT_ID=mcp-gateway-m2m" >> "$OUTPUT_FILE"
    echo "KEYCLOAK_M2M_CLIENT_SECRET=$M2M_SECRET" >> "$OUTPUT_FILE"
fi
chmod 600 "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}Credentials saved to: $(pwd)/$OUTPUT_FILE${NC}"
echo -e "${YELLOW}Note: Keep this file secure and add it to .gitignore!${NC}"

# Alternative Method 2: Using kcadm.sh (commented out as it's more complex)
# echo ""
# echo "Alternative Method 2: Using Keycloak Admin CLI (kcadm.sh)..."
# docker exec $KEYCLOAK_CONTAINER /opt/keycloak/bin/kcadm.sh config credentials \
#     --server $KEYCLOAK_URL --realm master --user $ADMIN_USER --password "$ADMIN_PASS"
# docker exec $KEYCLOAK_CONTAINER /opt/keycloak/bin/kcadm.sh get clients \
#     -r $REALM --fields clientId,secret