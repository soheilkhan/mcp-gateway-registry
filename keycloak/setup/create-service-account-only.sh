#!/bin/bash
# Simple script to create the missing service account user

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
SERVICE_ACCOUNT="service-account-mcp-gateway-m2m"

echo "Creating service account user: $SERVICE_ACCOUNT"

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

# Check if service account user exists
echo "Checking if service account exists..."
USER_EXISTS=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$ADMIN_URL/admin/realms/$REALM/users?username=$SERVICE_ACCOUNT" | jq -r '.[0].id // empty')

if [ ! -z "$USER_EXISTS" ]; then
    echo "Service account user already exists with ID: $USER_EXISTS"
else
    echo "Creating service account user..."
    
    # Create the service account user
    USER_JSON='{
        "username": "'$SERVICE_ACCOUNT'",
        "enabled": true,
        "emailVerified": true,
        "serviceAccountClientId": "mcp-gateway-m2m"
    }'
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$ADMIN_URL/admin/realms/$REALM/users" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$USER_JSON")
    
    if [ "$RESPONSE" = "201" ]; then
        echo "Service account user created successfully!"
        
        # Get the user ID
        USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
            "$ADMIN_URL/admin/realms/$REALM/users?username=$SERVICE_ACCOUNT" | jq -r '.[0].id')
        
        echo "User ID: $USER_ID"
    else
        echo "Failed to create user. HTTP: $RESPONSE"
        exit 1
    fi
fi

# Get user ID for group assignment
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$ADMIN_URL/admin/realms/$REALM/users?username=$SERVICE_ACCOUNT" | jq -r '.[0].id')

# Get group ID for mcp-servers-unrestricted
echo "Finding mcp-servers-unrestricted group..."
GROUP_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$ADMIN_URL/admin/realms/$REALM/groups" | jq -r '.[] | select(.name=="mcp-servers-unrestricted") | .id')

if [ ! -z "$GROUP_ID" ] && [ "$GROUP_ID" != "null" ]; then
    echo "Found group ID: $GROUP_ID"
    
    # Assign user to group
    GROUP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "$ADMIN_URL/admin/realms/$REALM/users/$USER_ID/groups/$GROUP_ID" \
        -H "Authorization: Bearer $TOKEN")
    
    if [ "$GROUP_RESPONSE" = "204" ]; then
        echo "Service account assigned to mcp-servers-unrestricted group!"
        echo ""
        echo "SUCCESS! Now generate a new M2M token to get the group membership."
    else
        echo "Failed to assign to group. HTTP: $GROUP_RESPONSE"
    fi
else
    echo "Could not find mcp-servers-unrestricted group"
    
    # List available groups
    echo "Available groups:"
    curl -s -H "Authorization: Bearer $TOKEN" \
        "$ADMIN_URL/admin/realms/$REALM/groups" | jq -r '.[].name'
fi