#!/bin/bash
# Add groups mapper to the M2M client so groups appear in JWT tokens

set -e

# Use localhost for admin API
ADMIN_URL="http://localhost:8080"
REALM="mcp-gateway"
ADMIN_USER="admin"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD}"

# Check required environment variables
if [ -z "$ADMIN_PASS" ]; then
    echo "Error: KEYCLOAK_ADMIN_PASSWORD environment variable is required"
    echo "Please set it before running this script:"
    echo "export KEYCLOAK_ADMIN_PASSWORD=\"your-secure-password\""
    exit 1
fi

echo "Adding groups mapper to mcp-gateway-m2m client..."

# Get admin token
echo "Getting admin token..."
TOKEN=$(curl -s -X POST "$ADMIN_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASS" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
    echo "Failed to get admin token"
    exit 1
fi

echo "Got admin token successfully"

# Get M2M client ID
echo "Finding mcp-gateway-m2m client..."
CLIENT_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$ADMIN_URL/admin/realms/$REALM/clients?clientId=mcp-gateway-m2m" | \
    jq -r '.[0].id // empty')

if [ -z "$CLIENT_ID" ]; then
    echo "M2M client not found"
    exit 1
fi

echo "Found M2M client with ID: $CLIENT_ID"

# Create groups mapper JSON
GROUPS_MAPPER='{
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-group-membership-mapper",
    "consentRequired": false,
    "config": {
        "full.path": "false",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "groups",
        "userinfo.token.claim": "true"
    }
}'

# Add the groups mapper
echo "Adding groups mapper..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$ADMIN_URL/admin/realms/$REALM/clients/$CLIENT_ID/protocol-mappers/models" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$GROUPS_MAPPER")

if [ "$RESPONSE" = "201" ]; then
    echo "Groups mapper added successfully!"
    echo ""
    echo "SUCCESS! The M2M client now has a groups mapper."
    echo "Generate a new M2M token to get group membership in the JWT."
elif [ "$RESPONSE" = "409" ]; then
    echo "Groups mapper already exists - that's fine!"
else
    echo "Failed to add groups mapper. HTTP: $RESPONSE"
    exit 1
fi