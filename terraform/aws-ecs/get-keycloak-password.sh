#!/bin/bash

# Get Keycloak Admin Password from AWS Secrets Manager
# This script retrieves the auto-generated Keycloak admin password
# and stores it in a local .admin_password file for easy reference

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWORD_FILE="${SCRIPT_DIR}/.admin_password"
REGION="${AWS_REGION:-us-east-1}"
SECRET_PREFIX="mcp-gateway-keycloak-admin-password"

echo -e "${YELLOW}Retrieving Keycloak admin password from AWS Secrets Manager...${NC}"

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    echo "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Get the secret name (it has a random suffix)
SECRET_NAME=$(aws secretsmanager list-secrets --region "$REGION" \
    --filters Key=name,Values="$SECRET_PREFIX" \
    --query 'SecretList[0].Name' \
    --output text 2>/dev/null)

if [ -z "$SECRET_NAME" ] || [ "$SECRET_NAME" = "None" ]; then
    echo -e "${RED}Error: Could not find secret starting with '$SECRET_PREFIX' in region '$REGION'${NC}"
    echo "Make sure:"
    echo "  1. Terraform deployment has completed successfully"
    echo "  2. AWS credentials are configured (run: aws sts get-caller-identity)"
    echo "  3. You're in the correct AWS region"
    exit 1
fi

# Retrieve the password
PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null)

if [ -z "$PASSWORD" ]; then
    echo -e "${RED}Error: Could not retrieve password from secret${NC}"
    exit 1
fi

# Store in file
echo "$PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

echo -e "${GREEN}Success!${NC}"
echo ""
echo "Keycloak Admin Credentials:"
echo "  Username: admin"
echo "  Password: (stored in $PASSWORD_FILE)"
echo ""
echo "Admin Console URL: https://kc.mycorp.click/admin/master/console/"
echo ""
echo -e "${YELLOW}Note: The password file is in .gitignore and will not be committed to git${NC}"
