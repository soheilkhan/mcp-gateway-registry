#!/bin/bash
set -e

# Determine the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Load environment variables from .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

# Use environment variables or defaults for testing
KEYCLOAK_EXTERNAL_URL="${KEYCLOAK_EXTERNAL_URL:-http://localhost:8080}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-mcp-gateway}"
KEYCLOAK_M2M_CLIENT_ID="${KEYCLOAK_M2M_CLIENT_ID:-mcp-gateway-m2m}"
KEYCLOAK_M2M_CLIENT_SECRET="${KEYCLOAK_M2M_CLIENT_SECRET}"
REGISTRY_URL="${REGISTRY_URL:-http://localhost}"

# Check for required credentials
if [ -z "$KEYCLOAK_M2M_CLIENT_SECRET" ]; then
    echo "ERROR: KEYCLOAK_M2M_CLIENT_SECRET not set"
    echo "Please set it in .env file or export it as an environment variable"
    echo ""
    echo "To get the secret:"
    echo "  1. Run: cd ../keycloak/setup && ./init-keycloak.sh"
    echo "  2. Or check Keycloak Admin Console → Clients → mcp-gateway-m2m → Credentials"
    exit 1
fi

echo "=== Testing MCP Gateway ==="
echo ""
echo "Configuration:"
echo "  Keycloak URL: $KEYCLOAK_EXTERNAL_URL"
echo "  Realm: $KEYCLOAK_REALM"
echo "  Client ID: $KEYCLOAK_M2M_CLIENT_ID"
echo "  Registry URL: $REGISTRY_URL"
echo ""

# Step 1: Get M2M token from Keycloak
echo "1. Getting M2M token from Keycloak..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_EXTERNAL_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials' \
  -d "client_id=${KEYCLOAK_M2M_CLIENT_ID}" \
  -d "client_secret=${KEYCLOAK_M2M_CLIENT_SECRET}" \
  -d 'scope=openid')

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get token"
  echo "$TOKEN_RESPONSE" | jq .
  exit 1
fi

echo "✓ Got token: ${TOKEN:0:50}..."
echo ""

# Step 2: Test ping endpoint
echo "2. Testing /mcpgw/mcp ping endpoint..."
PING_RESPONSE=$(curl -s -X POST "${REGISTRY_URL}/mcpgw/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc": "2.0", "method": "ping", "id": 1}')

echo "Response:"
echo "$PING_RESPONSE" | jq . 2>/dev/null || echo "$PING_RESPONSE"
echo ""

# Step 3: Test initialize
echo "3. Testing initialize..."
INIT_RESPONSE=$(curl -s -X POST "${REGISTRY_URL}/mcpgw/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 2}')

echo "Response:"
echo "$INIT_RESPONSE" | jq . 2>/dev/null || echo "$INIT_RESPONSE"
echo ""

echo "=== Test Complete ==="
