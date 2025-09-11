#!/bin/bash
# Assign the M2M service account to the required groups

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="mcp-gateway"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"
SERVICE_ACCOUNT_USERNAME="service-account-mcp-gateway-m2m"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Assigning M2M service account to groups${NC}"
echo "=============================================="

# Function to get admin token
get_admin_token() {
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KEYCLOAK_ADMIN}" \
        -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    echo "$response" | jq -r '.access_token // empty'
}

# Function to assign service account to groups
assign_service_account_groups() {
    local token=$1
    
    echo "Finding service account user: $SERVICE_ACCOUNT_USERNAME"
    
    # Get service account user ID
    local user_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=$SERVICE_ACCOUNT_USERNAME" | \
        jq -r '.[0].id // empty')
    
    if [ -z "$user_id" ]; then
        echo -e "${RED}Error: Service account user '$SERVICE_ACCOUNT_USERNAME' not found${NC}"
        return 1
    fi
    
    echo "Found service account user ID: $user_id"
    
    # Get the mcp-servers-unrestricted group ID
    local group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-servers-unrestricted") | .id // empty')
    
    if [ -z "$group_id" ]; then
        echo -e "${RED}Error: Group 'mcp-servers-unrestricted' not found${NC}"
        echo "Available groups:"
        curl -s -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
            jq -r '.[].name'
        return 1
    fi
    
    echo "Found group 'mcp-servers-unrestricted' with ID: $group_id"
    
    # Assign user to group
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$user_id/groups/$group_id" \
        -H "Authorization: Bearer ${token}")
    
    if [ "$response" = "204" ]; then
        echo -e "${GREEN}Successfully assigned service account to 'mcp-servers-unrestricted' group!${NC}"
    else
        echo -e "${RED}Failed to assign service account to group (HTTP $response)${NC}"
        return 1
    fi
    
    # Verify the assignment
    echo "Verifying group membership..."
    local groups=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$user_id/groups" | \
        jq -r '.[].name')
    
    echo "Service account is now member of groups:"
    echo "$groups" | sed 's/^/  - /'
    
    return 0
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
        echo "Environment variables loaded"
    else
        echo -e "${RED}No .env file found at $ENV_FILE${NC}"
        exit 1
    fi
    
    # Check if admin password is set
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        echo -e "${RED}Error: KEYCLOAK_ADMIN_PASSWORD environment variable is not set${NC}"
        exit 1
    fi
    
    # Get admin token
    echo "Authenticating with Keycloak..."
    TOKEN=$(get_admin_token)
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Error: Failed to authenticate with Keycloak${NC}"
        echo "Please check your admin credentials and Keycloak connectivity"
        exit 1
    fi
    
    echo -e "${GREEN}Authentication successful!${NC}"
    
    # Assign service account to groups
    if assign_service_account_groups "$TOKEN"; then
        echo ""
        echo -e "${GREEN}Setup complete!${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Generate a new M2M token (the current one won't have the new group)"
        echo "2. Test the MCP Gateway with the new token"
        echo ""
        echo "The service account now has access to all MCP servers via the 'mcp-servers-unrestricted' group."
    else
        exit 1
    fi
}

# Run main function
main