#!/bin/bash
# Add MCP scopes to existing Keycloak setup
# This script adds the required MCP scopes to the M2M client

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="mcp-gateway"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Adding MCP scopes to existing Keycloak setup${NC}"
echo "=============================================="

# Function to get admin token
get_admin_token() {
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KEYCLOAK_ADMIN}" \
        -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4
}

# Function to create custom scopes
create_scopes() {
    local token=$1
    
    echo "Creating custom MCP scopes..."
    
    local scopes=("mcp-servers-unrestricted/read" "mcp-servers-unrestricted/execute" "mcp-servers-restricted/read" "mcp-servers-restricted/execute")
    
    for scope in "${scopes[@]}"; do
        local scope_json='{
            "name": "'$scope'",
            "description": "MCP Gateway scope for '$scope' access",
            "protocol": "openid-connect"
        }'
        
        local response=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$scope_json")
        
        if [ "$response" = "201" ]; then
            echo "  - Created scope: $scope"
        elif [ "$response" = "409" ]; then
            echo "  - Scope already exists: $scope"
        else
            echo -e "${RED}  - Failed to create scope: $scope (HTTP $response)${NC}"
        fi
    done
    
    echo -e "${GREEN}Custom scopes created successfully!${NC}"
}

# Function to assign scopes to M2M client
setup_m2m_scopes() {
    local token=$1
    
    echo "Setting up M2M client scopes..."
    
    # Get M2M client ID
    local m2m_client_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=mcp-gateway-m2m" | \
        jq -r '.[0].id')
    
    if [ -z "$m2m_client_id" ] || [ "$m2m_client_id" = "null" ]; then
        echo -e "${RED}Error: Could not find mcp-gateway-m2m client${NC}"
        return 1
    fi
    
    echo "Found M2M client ID: $m2m_client_id"
    
    # Get all available client scopes
    local scopes=("mcp-servers-unrestricted/read" "mcp-servers-unrestricted/execute" "mcp-servers-restricted/read" "mcp-servers-restricted/execute")
    
    for scope in "${scopes[@]}"; do
        # Get scope ID
        local scope_id=$(curl -s -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | \
            jq -r '.[] | select(.name=="'$scope'") | .id')
        
        if [ ! -z "$scope_id" ] && [ "$scope_id" != "null" ]; then
            echo "Found scope ID for $scope: $scope_id"
            
            # Add scope as default client scope
            local response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${m2m_client_id}/default-client-scopes/${scope_id}" \
                -H "Authorization: Bearer ${token}")
            
            if [ "$response" = "204" ]; then
                echo "  - Assigned scope: $scope"
            else
                echo -e "${YELLOW}  - Warning: Could not assign scope $scope (HTTP $response)${NC}"
            fi
        else
            echo -e "${RED}  - Error: Could not find scope: $scope${NC}"
        fi
    done
    
    echo -e "${GREEN}M2M client scopes configured successfully!${NC}"
}

# Main execution
main() {
    # Get script directory and find .env file
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
    ENV_FILE="$PROJECT_ROOT/.env"
    
    # Load environment variables from .env file if it exists
    if [ -f "$ENV_FILE" ]; then
        echo "Loading environment variables from $ENV_FILE..."
        set -a  # Automatically export all variables
        source "$ENV_FILE"
        set +a  # Turn off automatic export
        echo "Environment variables loaded successfully"
    else
        echo "No .env file found at $ENV_FILE"
        exit 1
    fi
    
    # Check if admin password is set
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        echo -e "${RED}Error: KEYCLOAK_ADMIN_PASSWORD environment variable is not set${NC}"
        echo "Please set it in .env file or export it before running this script"
        exit 1
    fi
    
    # Get admin token
    echo "Authenticating with Keycloak..."
    TOKEN=$(get_admin_token)
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Error: Failed to authenticate with Keycloak${NC}"
        echo "Please check your admin credentials"
        exit 1
    fi
    
    echo -e "${GREEN}Authentication successful!${NC}"
    
    # Create scopes and assign them to M2M client
    create_scopes "$TOKEN"
    setup_m2m_scopes "$TOKEN"
    
    echo ""
    echo -e "${GREEN}MCP scopes setup complete!${NC}"
    echo ""
    echo "The mcp-gateway-m2m client now has the following scopes:"
    echo "  - mcp-servers-unrestricted/read"
    echo "  - mcp-servers-unrestricted/execute"
    echo "  - mcp-servers-restricted/read"
    echo "  - mcp-servers-restricted/execute"
    echo ""
    echo -e "${YELLOW}You will need to generate a new M2M token to get these scopes.${NC}"
}

# Run main function
main