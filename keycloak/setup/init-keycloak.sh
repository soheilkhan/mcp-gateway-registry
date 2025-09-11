#!/bin/bash
# Initialize Keycloak with MCP Gateway configuration
# This script sets up the initial realm, clients, groups, and users

set -e

# Use admin URL for API calls, fallback to localhost
KEYCLOAK_ADMIN_URL_OVERRIDE="${KEYCLOAK_ADMIN_URL:-http://localhost:8080}"
KEYCLOAK_URL="$KEYCLOAK_ADMIN_URL_OVERRIDE"
REALM="mcp-gateway"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Keycloak initialization script for MCP Gateway Registry${NC}"
echo "=============================================="

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
    echo -n "Waiting for Keycloak to be ready..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Try to access the admin console which indicates Keycloak is ready
        if curl -f -s "${KEYCLOAK_URL}/admin/" > /dev/null 2>&1; then
            echo -e " ${GREEN}Ready!${NC}"
            return 0
        fi
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e " ${RED}Timeout!${NC}"
    echo "Keycloak did not become ready within 5 minutes"
    exit 1
}

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

# Function to check if realm exists
realm_exists() {
    local token=$1
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}")
    
    [ "$response" = "200" ]
}

# Function to create realm step by step
create_realm() {
    local token=$1
    
    echo "Creating MCP Gateway realm..."
    
    # Check if realm already exists
    if realm_exists "$token"; then
        echo -e "${YELLOW}Realm already exists. Skipping creation...${NC}"
        return 0
    fi
    
    # Create basic realm
    local realm_json='{
        "realm": "mcp-gateway",
        "enabled": true,
        "registrationAllowed": false,
        "loginWithEmailAllowed": true,
        "duplicateEmailsAllowed": false,
        "resetPasswordAllowed": true,
        "editUsernameAllowed": false
    }'
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${KEYCLOAK_URL}/admin/realms" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$realm_json")
    
    if [ "$response" = "201" ]; then
        echo -e "${GREEN}Realm created successfully!${NC}"
        return 0
    elif [ "$response" = "409" ]; then
        echo -e "${YELLOW}Realm already exists. Continuing...${NC}"
        return 0
    else
        echo -e "${RED}Failed to create realm. HTTP status: ${response}${NC}"
        echo "Response body:"
        curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$realm_json"
        echo ""
        return 1
    fi
}

# Function to create clients
create_clients() {
    local token=$1
    
    echo "Creating OAuth2 clients..."
    
    # Create web client
    local web_client_json='{
        "clientId": "mcp-gateway-web",
        "name": "MCP Gateway Web Client",
        "enabled": true,
        "clientAuthenticatorType": "client-secret",
        "redirectUris": [
            "'${AUTH_SERVER_EXTERNAL_URL:-http://localhost:8888}'/oauth2/callback/keycloak",
            "'${REGISTRY_URL:-http://localhost:7860}'/*",
            "http://localhost:7860/*",
            "http://localhost:8888/*"
        ],
        "webOrigins": [
            "'${REGISTRY_URL:-http://localhost:7860}'",
            "http://localhost:7860",
            "+"
        ],
        "protocol": "openid-connect",
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false,
        "directAccessGrantsEnabled": true,
        "serviceAccountsEnabled": false,
        "publicClient": false
    }'
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$web_client_json" > /dev/null
    
    # Create M2M client
    local m2m_client_json='{
        "clientId": "mcp-gateway-m2m",
        "name": "MCP Gateway M2M Client",
        "enabled": true,
        "clientAuthenticatorType": "client-secret",
        "protocol": "openid-connect",
        "standardFlowEnabled": false,
        "implicitFlowEnabled": false,
        "directAccessGrantsEnabled": false,
        "serviceAccountsEnabled": true,
        "publicClient": false
    }'
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$m2m_client_json" > /dev/null
    
    echo -e "${GREEN}Clients created successfully!${NC}"
}

# Function to create groups
create_groups() {
    local token=$1
    
    echo "Creating user groups..."
    
    local groups=("mcp-registry-admin" "mcp-registry-user" "mcp-registry-developer" "mcp-registry-operator" "mcp-servers-unrestricted" "mcp-servers-restricted")
    
    for group in "${groups[@]}"; do
        local group_json='{
            "name": "'$group'",
            "attributes": {
                "description": ["'$group' group for MCP Gateway access"]
            }
        }'
        
        curl -s -X POST "${KEYCLOAK_URL}/admin/realms/mcp-gateway/groups" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$group_json" > /dev/null
    done
    
    echo -e "${GREEN}Groups created successfully!${NC}"
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
    
    # Get all available client scopes
    local scopes=("mcp-servers-unrestricted/read" "mcp-servers-unrestricted/execute" "mcp-servers-restricted/read" "mcp-servers-restricted/execute")
    
    for scope in "${scopes[@]}"; do
        # Get scope ID
        local scope_id=$(curl -s -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | \
            jq -r '.[] | select(.name=="'$scope'") | .id')
        
        if [ ! -z "$scope_id" ] && [ "$scope_id" != "null" ]; then
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

# Function to create service account user for M2M client
create_service_account_user() {
    local token=$1
    local service_account_username="service-account-mcp-gateway-m2m"
    
    echo "Creating service account user: $service_account_username"
    
    # Check if user already exists
    local existing_user=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=$service_account_username" | \
        jq -r '.[0].id // empty')
    
    if [ ! -z "$existing_user" ]; then
        echo -e "${YELLOW}Service account user already exists with ID: $existing_user${NC}"
        return 0
    fi
    
    # Create service account user
    local user_json='{
        "username": "'$service_account_username'",
        "enabled": true,
        "emailVerified": true,
        "serviceAccountClientId": "mcp-gateway-m2m"
    }'
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$user_json")
    
    if [ "$response" = "201" ]; then
        echo -e "${GREEN}Service account user created successfully!${NC}"
        
        # Get the newly created user ID
        local user_id=$(curl -s -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=$service_account_username" | \
            jq -r '.[0].id')
        
        echo "Created service account user with ID: $user_id"
        
        # Assign user to mcp-servers-unrestricted group
        local group_id=$(curl -s -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
            jq -r '.[] | select(.name=="mcp-servers-unrestricted") | .id')
        
        if [ ! -z "$group_id" ] && [ "$group_id" != "null" ]; then
            local group_response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$user_id/groups/$group_id" \
                -H "Authorization: Bearer ${token}")
            
            if [ "$group_response" = "204" ]; then
                echo -e "${GREEN}Service account assigned to mcp-servers-unrestricted group!${NC}"
            else
                echo -e "${YELLOW}Warning: Could not assign service account to group (HTTP $group_response)${NC}"
            fi
        else
            echo -e "${RED}Error: Could not find mcp-servers-unrestricted group${NC}"
        fi
        
        return 0
    elif [ "$response" = "409" ]; then
        echo -e "${YELLOW}Service account user already exists. Continuing...${NC}"
        return 0
    else
        echo -e "${RED}Failed to create service account user. HTTP status: ${response}${NC}"
        return 1
    fi
}

# Function to create test users
create_users() {
    local token=$1
    
    echo "Creating test users..."
    
    # Define usernames for consistency
    local admin_username="admin"
    local test_username="testuser"
    
    # Create admin user
    local admin_user_json='{
        "username": "'$admin_username'",
        "email": "'$admin_username'@example.com",
        "enabled": true,
        "emailVerified": true,
        "firstName": "Admin",
        "lastName": "User",
        "credentials": [
            {
                "type": "password",
                "value": "'${INITIAL_ADMIN_PASSWORD:-changeme}'",
                "temporary": false
            }
        ]
    }'
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$admin_user_json" > /dev/null
    
    # Create test user
    local test_user_json='{
        "username": "'$test_username'",
        "email": "'$test_username'@example.com",
        "enabled": true,
        "emailVerified": true,
        "firstName": "Test",
        "lastName": "User",
        "credentials": [
            {
                "type": "password",
                "value": "'${INITIAL_USER_PASSWORD:-testpass}'",
                "temporary": false
            }
        ]
    }'
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$test_user_json" > /dev/null
    
    echo "Assigning users to groups..."
    
    # Get user IDs
    local admin_user_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=$admin_username" | \
        jq -r '.[0].id')
    
    local test_user_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=$test_username" | \
        jq -r '.[0].id')
    
    # Get all group IDs
    local admin_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-registry-admin") | .id')
    
    local user_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-registry-user") | .id')
    
    local developer_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-registry-developer") | .id')
    
    local operator_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-registry-operator") | .id')
    
    local unrestricted_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-servers-unrestricted") | .id')
    
    local restricted_group_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" | \
        jq -r '.[] | select(.name=="mcp-servers-restricted") | .id')
    
    # Define usernames for consistent logging
    local admin_username="admin"
    local test_username="testuser"
    
    # Assign admin user to admin group and unrestricted servers group
    if [ ! -z "$admin_user_id" ] && [ ! -z "$admin_group_id" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$admin_user_id/groups/$admin_group_id" \
            -H "Authorization: Bearer ${token}" > /dev/null
        echo "  - $admin_username assigned to mcp-registry-admin group"
    fi
    
    # Also assign admin to unrestricted servers group for full access
    if [ ! -z "$admin_user_id" ] && [ ! -z "$unrestricted_group_id" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$admin_user_id/groups/$unrestricted_group_id" \
            -H "Authorization: Bearer ${token}" > /dev/null
        echo "  - $admin_username assigned to mcp-servers-unrestricted group"
    fi
    
    # Assign test user to all groups except admin
    if [ ! -z "$test_user_id" ]; then
        # Arrays of group IDs and names for loop processing
        local group_ids=("$user_group_id" "$developer_group_id" "$operator_group_id" "$unrestricted_group_id" "$restricted_group_id")
        local group_names=("mcp-registry-user" "mcp-registry-developer" "mcp-registry-operator" "mcp-servers-unrestricted" "mcp-servers-restricted")
        
        # Loop through groups and assign test user to each
        for i in "${!group_ids[@]}"; do
            local group_id="${group_ids[$i]}"
            local group_name="${group_names[$i]}"
            
            if [ ! -z "$group_id" ]; then
                curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/$test_user_id/groups/$group_id" \
                    -H "Authorization: Bearer ${token}" > /dev/null
                echo "  - $test_username assigned to $group_name group"
            fi
        done
    fi
    
    echo -e "${GREEN}Users created and assigned to groups successfully!${NC}"
}

# Function to create client secrets
setup_client_secrets() {
    local token=$1
    
    echo "Setting up client secrets..."
    
    # Get web client ID
    local web_client_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=mcp-gateway-web" | \
        jq -r '.[0].id')
    
    # Generate secret for web client
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${web_client_id}/client-secret" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" > /dev/null
    
    local web_secret_response=$(curl -s "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${web_client_id}/client-secret" \
        -H "Authorization: Bearer ${token}")
    web_secret=$(echo "$web_secret_response" | jq -r '.value // empty')
    
    # Get M2M client ID
    local m2m_client_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=mcp-gateway-m2m" | \
        jq -r '.[0].id')
    
    # Generate secret for M2M client
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${m2m_client_id}/client-secret" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" > /dev/null
    
    local m2m_secret_response=$(curl -s "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${m2m_client_id}/client-secret" \
        -H "Authorization: Bearer ${token}")
    m2m_secret=$(echo "$m2m_secret_response" | jq -r '.value // empty')
    
    echo -e "${GREEN}Client secrets generated!${NC}"
    echo ""
    echo "=============================================="
    echo -e "${YELLOW}IMPORTANT: Save these client secrets:${NC}"
    echo "=============================================="
    echo "KEYCLOAK_CLIENT_ID=mcp-gateway-web"
    echo "KEYCLOAK_CLIENT_SECRET=${web_secret}"
    echo ""
    echo "KEYCLOAK_M2M_CLIENT_ID=mcp-gateway-m2m"
    echo "KEYCLOAK_M2M_CLIENT_SECRET=${m2m_secret}"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Copy the above values to your .env file"
    echo "2. Update these environment variables in .env:"
    echo "   - KEYCLOAK_CLIENT_SECRET=${web_secret}"
    echo "   - KEYCLOAK_M2M_CLIENT_SECRET=${m2m_secret}"
    echo ""
    
    # Save to file for reference
    local output_file="keycloak-client-secrets.txt"
    echo "# Keycloak Client Credentials - Generated $(date)" > "$output_file"
    echo "# Add these to your .env file" >> "$output_file"
    echo "" >> "$output_file"
    echo "KEYCLOAK_CLIENT_ID=mcp-gateway-web" >> "$output_file"
    echo "KEYCLOAK_CLIENT_SECRET=${web_secret}" >> "$output_file"
    echo "" >> "$output_file"
    echo "KEYCLOAK_M2M_CLIENT_ID=mcp-gateway-m2m" >> "$output_file"
    echo "KEYCLOAK_M2M_CLIENT_SECRET=${m2m_secret}" >> "$output_file"
    echo "" >> "$output_file"
    chmod 600 "$output_file"
    echo -e "${GREEN}Credentials also saved to: $(pwd)/$output_file${NC}"
    echo -e "${YELLOW}Note: This file contains sensitive credentials. Keep it secure!${NC}"
}

# Function to setup groups mapper for the web client
setup_groups_mapper() {
    local token=$1
    
    echo "Setting up groups mapper for OAuth2 client..."
    
    # Get web client ID
    local web_client_id=$(curl -s -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=mcp-gateway-web" | \
        jq -r '.[0].id')
    
    if [ -z "$web_client_id" ] || [ "$web_client_id" = "null" ]; then
        echo -e "${RED}Error: Could not find mcp-gateway-web client${NC}"
        return 1
    fi
    
    # Create groups mapper JSON
    local groups_mapper_json='{
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
    
    # Add the groups mapper to the client
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${web_client_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$groups_mapper_json")
    
    if [ "$response" = "201" ]; then
        echo -e "${GREEN}Groups mapper created successfully!${NC}"
    elif [ "$response" = "409" ]; then
        echo -e "${YELLOW}Groups mapper already exists. Continuing...${NC}"
    else
        echo -e "${RED}Failed to create groups mapper. HTTP status: ${response}${NC}"
        return 1
    fi
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
        echo "DEBUG: KEYCLOAK_ADMIN_PASSWORD = ${KEYCLOAK_ADMIN_PASSWORD:-NOT_SET}"
        echo "DEBUG: KEYCLOAK_ADMIN = ${KEYCLOAK_ADMIN:-NOT_SET}"
        echo "DEBUG: KEYCLOAK_URL = ${KEYCLOAK_URL:-NOT_SET}"
    else
        echo "No .env file found at $ENV_FILE"
        echo "Current directory: $(pwd)"
        echo "Script directory: $SCRIPT_DIR"
        echo "Project root: $PROJECT_ROOT"
    fi
    
    # Check if admin password is set
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        echo -e "${RED}Error: KEYCLOAK_ADMIN_PASSWORD environment variable is not set${NC}"
        echo "Please set it in .env file or export it before running this script"
        exit 1
    fi
    
    # Wait for Keycloak to be ready
    wait_for_keycloak
    
    # Get admin token
    echo "Authenticating with Keycloak..."
    TOKEN=$(get_admin_token)
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Error: Failed to authenticate with Keycloak${NC}"
        echo "Please check your admin credentials"
        exit 1
    fi
    
    echo -e "${GREEN}Authentication successful!${NC}"
    
    # Create realm and configure it step by step
    if create_realm "$TOKEN"; then
        create_clients "$TOKEN"
        create_scopes "$TOKEN"
        create_groups "$TOKEN"
        create_users "$TOKEN"
        create_service_account_user "$TOKEN"
        setup_client_secrets "$TOKEN"
        setup_groups_mapper "$TOKEN"
        setup_m2m_scopes "$TOKEN"
    else
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}Keycloak initialization complete!${NC}"
    echo ""
    echo "You can now access Keycloak at: ${KEYCLOAK_URL}"
    echo "Admin console: ${KEYCLOAK_URL}/admin"
    echo "Realm: ${REALM}"
    echo ""
    echo "Default users created:"
    echo "  - admin/changeme (admin access)"
    echo "  - testuser/testpass (user access)"
    echo ""
    echo -e "${YELLOW}Remember to change the default passwords!${NC}"
}

# Run main function
main