#!/bin/bash

# Initialize Keycloak after HTTPS deployment
# This script updates the security-admin-console client to work with HTTPS URLs

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_FILE="${SCRIPT_DIR}/.resources"

# Load resources from file if it exists
if [ -f "${RESOURCES_FILE}" ]; then
    source "${RESOURCES_FILE}"
fi

# Configuration
KEYCLOAK_URL="${1:-https://kc.mycorp.click}"
ALB_URL="${ALB_KEYCLOAK_DNS:-}"

echo "Keycloak HTTPS Configuration"
echo "===================================="
echo "Keycloak URL: $KEYCLOAK_URL"
if [ -n "$ALB_URL" ]; then
    echo "ALB URL: https://$ALB_URL"
fi
echo ""

# Get Keycloak admin password from Secrets Manager
echo "Retrieving Keycloak admin password from AWS Secrets Manager..."
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI not found. Please install it first."
    exit 1
fi

# Find the secret by name pattern (handles dynamic secret IDs)
SECRET_NAME=$(aws secretsmanager list-secrets \
    --region us-east-1 \
    --query 'SecretList[?contains(Name, `keycloak-admin-password`)].Name' \
    --output text 2>/dev/null | head -n1)

if [ -z "$SECRET_NAME" ]; then
    echo "ERROR: Could not find Keycloak admin password secret"
    echo "Looking for secret with name pattern: *keycloak-admin-password*"
    exit 1
fi

echo "Found secret: $SECRET_NAME"

ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region us-east-1 \
    --query 'SecretString' \
    --output text 2>/dev/null || echo "")

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "ERROR: Failed to retrieve admin password from Secrets Manager"
    echo "Make sure AWS CLI is configured and you have access to the secret"
    exit 1
fi

echo "Admin password retrieved successfully"
echo ""

# Run Python script to update Keycloak configuration
export KEYCLOAK_URL
export ADMIN_PASSWORD
export ALB_URL

python3 << 'PYTHON_EOF'
import requests
import json
import sys
import os
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL', 'https://kc.mycorp.click')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', '')
ALB_URL = os.environ.get('ALB_URL', '')
ADMIN_USER = 'admin'

print("=" * 70)
print("KEYCLOAK CONFIGURATION SCRIPT - VERBOSE MODE")
print("=" * 70)
print(f"Keycloak URL: {KEYCLOAK_URL}")
print(f"Admin user: {ADMIN_USER}")
print(f"ALB URL: {ALB_URL if ALB_URL else 'Not configured'}")
print(f"Password length: {len(ADMIN_PASSWORD)} characters")
print("=" * 70)
print()

# Get token
token_url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
print(f"Step 1: Getting admin token from {token_url}")
print(f"Request: POST {token_url}")
print(f"  - grant_type: password")
print(f"  - client_id: admin-cli")
print(f"  - username: {ADMIN_USER}")
print(f"  - password: {'*' * len(ADMIN_PASSWORD)}")
print()

try:
    token_resp = requests.post(
        token_url,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data={
            "username": ADMIN_USER,
            "password": ADMIN_PASSWORD,
            "grant_type": "password",
            "client_id": "admin-cli"
        },
        timeout=10,
        verify=False
    )
    print(f"Response: {token_resp.status_code} {token_resp.reason}")
    print(f"Response headers: {dict(token_resp.headers)}")
except Exception as e:
    print(f"ERROR: Failed to connect to Keycloak: {e}")
    print(f"Exception type: {type(e).__name__}")
    sys.exit(1)

if token_resp.status_code != 200:
    print(f"ERROR: Token request failed with status {token_resp.status_code}")
    print(f"Response body: {token_resp.text}")
    sys.exit(1)

try:
    token_data = token_resp.json()
    TOKEN = token_data["access_token"]
    print(f"✓ Token obtained successfully")
    print(f"  Token type: {token_data.get('token_type', 'N/A')}")
    print(f"  Expires in: {token_data.get('expires_in', 'N/A')} seconds")
    print(f"  Token length: {len(TOKEN)} characters")
    print(f"  Token preview: {TOKEN[:20]}...{TOKEN[-20:]}")
except Exception as e:
    print(f"ERROR: Failed to parse token response: {e}")
    print(f"Response: {token_resp.text}")
    sys.exit(1)
print()

# Get the security-admin-console client
clients_url = f"{KEYCLOAK_URL}/admin/realms/master/clients?clientId=security-admin-console"
print(f"Step 2: Getting security-admin-console client")
print(f"Request: GET {clients_url}")
print(f"  Authorization: Bearer {TOKEN[:20]}...{TOKEN[-20:]}")
print()

try:
    clients_resp = requests.get(
        clients_url,
        headers={"Authorization": f"Bearer {TOKEN}"},
        verify=False,
        timeout=10
    )
    print(f"Response: {clients_resp.status_code} {clients_resp.reason}")
    print(f"Response headers: {dict(clients_resp.headers)}")
    print()
except Exception as e:
    print(f"ERROR: Failed to retrieve clients: {e}")
    print(f"Exception type: {type(e).__name__}")
    sys.exit(1)

if clients_resp.status_code == 401:
    print("=" * 70)
    print("ERROR: Admin user does not have permission to access admin API (401)")
    print("=" * 70)
    print("The admin token appears valid but doesn't have admin console permissions.")
    print()
    print("Response body:")
    print(clients_resp.text)
    print()
    print("Possible solutions:")
    print("1. Ensure you are using the correct admin password")
    print("2. Try accessing the Keycloak admin console manually and configure it there")
    print("3. Wait for Keycloak to fully initialize (5+ minutes)")
    print("4. Check if there's a redirect loop preventing proper initialization")
    print()
    print("Debug info:")
    print(f"  - Token length: {len(TOKEN)}")
    print(f"  - Keycloak URL: {KEYCLOAK_URL}")
    print(f"  - Request URL: {clients_url}")
    sys.exit(1)

elif clients_resp.status_code != 200:
    print(f"ERROR: Failed to get clients: {clients_resp.status_code}")
    print(f"Response body: {clients_resp.text}")
    sys.exit(1)

try:
    clients = clients_resp.json()
    print(f"✓ Received {len(clients)} client(s)")
except Exception as e:
    print(f"ERROR: Failed to parse clients response: {e}")
    print(f"Response: {clients_resp.text}")
    sys.exit(1)

if not clients:
    print("ERROR: security-admin-console client not found")
    sys.exit(1)

client = clients[0]
client_id = client["id"]
print(f"✓ Found client: {client_id}")
print(f"  Client name: {client.get('clientId', 'N/A')}")
print(f"  Client protocol: {client.get('protocol', 'N/A')}")
print(f"  Enabled: {client.get('enabled', 'N/A')}")
print()

print("Current redirect URIs:")
current_uris = client.get("redirectUris", [])
if current_uris:
    for uri in current_uris:
        print(f"  - {uri}")
else:
    print("  (none configured)")
print()

# Update redirect URIs
new_redirect_uris = [
    "http://localhost:8080/admin/master/console/",
    "http://localhost:8080/admin/realms/master/console/",
    "http://127.0.0.1:8080/admin/master/console/",
    "http://127.0.0.1:8080/admin/realms/master/console/",
    f"{KEYCLOAK_URL}/admin/master/console/",
    f"{KEYCLOAK_URL}/admin/realms/master/console/",
    f"{KEYCLOAK_URL}/admin/master/console",
    f"{KEYCLOAK_URL}/admin/realms/master/console"
]

# Add ALB URL if available
if ALB_URL:
    alb_uris = [
        f"https://{ALB_URL}/admin/master/console/",
        f"https://{ALB_URL}/admin/realms/master/console/",
        f"https://{ALB_URL}/admin/master/console",
        f"https://{ALB_URL}/admin/realms/master/console",
        f"http://{ALB_URL}:8080/admin/master/console/",
        f"http://{ALB_URL}:8080/admin/realms/master/console/"
    ]
    new_redirect_uris.extend(alb_uris)
    print(f"\nAdding ALB URLs: https://{ALB_URL}")

client["redirectUris"] = new_redirect_uris

# CRITICAL: Set webOrigins to allow CORS requests from the admin console
# The "+" value means "allow all origins from redirectUris"
# Without this, the admin console JavaScript cannot make API calls = spinner never loads!
client["webOrigins"] = [
    "+",  # Allow all origins from redirectUris
    KEYCLOAK_URL,
    f"{KEYCLOAK_URL}/*"
]

# Add ALB origin if available
if ALB_URL:
    client["webOrigins"].extend([
        f"https://{ALB_URL}",
        f"https://{ALB_URL}/*"
    ])

# Set explicit rootUrl and adminUrl to avoid ${authAdminUrl} variable issues
client["rootUrl"] = KEYCLOAK_URL
client["adminUrl"] = KEYCLOAK_URL
client["baseUrl"] = "/admin/master/console/"

# Ensure these flow settings are enabled for admin console to work
client["publicClient"] = True  # Admin console is a public client (no client secret)
# CRITICAL: Remove client authenticator type for public clients
# Public clients CANNOT use client-secret authentication
del client["clientAuthenticatorType"]  # Remove the conflicting setting
client["standardFlowEnabled"] = True  # Enable OAuth2 authorization code flow
client["directAccessGrantsEnabled"] = True  # Enable direct grants

# Send update
update_url = f"{KEYCLOAK_URL}/admin/realms/master/clients/{client_id}"
print(f"Step 3: Updating client configuration")
print(f"Request: PUT {update_url}")
print(f"  Authorization: Bearer {TOKEN[:20]}...{TOKEN[-20:]}")
print(f"  Content-Type: application/json")
print()
print("Configuration changes:")
print(f"  - rootUrl: {KEYCLOAK_URL}")
print(f"  - adminUrl: {KEYCLOAK_URL}")
print(f"  - baseUrl: /admin/master/console/")
print(f"  - publicClient: True")
print(f"  - standardFlowEnabled: True")
print(f"  - directAccessGrantsEnabled: True")
print(f"  - redirectUris: {len(new_redirect_uris)} URIs")
print(f"  - webOrigins: {len(client['webOrigins'])} origins (CRITICAL FIX FOR SPINNER ISSUE)")
for origin in client['webOrigins']:
    print(f"      {origin}")
print()

try:
    update_resp = requests.put(
        update_url,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json"
        },
        json=client,
        verify=False,
        timeout=10
    )
    print(f"Response: {update_resp.status_code} {update_resp.reason}")
    print(f"Response headers: {dict(update_resp.headers)}")
except Exception as e:
    print(f"ERROR: Failed to update client: {e}")
    print(f"Exception type: {type(e).__name__}")
    sys.exit(1)

if update_resp.status_code != 204:
    print(f"ERROR: Failed to update client: {update_resp.status_code}")
    print(f"Response body: {update_resp.text}")
    sys.exit(1)

print()
print("=" * 70)
print("SUCCESS! Client updated successfully")
print("=" * 70)
print()

print("Updated redirect URIs:")
for i, uri in enumerate(new_redirect_uris, 1):
    print(f"  {i}. {uri}")

print()
print("=" * 70)
print(f"You can now access the admin console at:")
print(f"  {KEYCLOAK_URL}/admin/master/console/")
print("=" * 70)

PYTHON_EOF
