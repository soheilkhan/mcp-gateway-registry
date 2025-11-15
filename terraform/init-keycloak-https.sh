#!/bin/bash

# Initialize Keycloak after HTTPS deployment
# This script updates the security-admin-console client to work with HTTPS URLs

set -e

# Configuration
KEYCLOAK_URL="${1:-https://kc.mycorp.click}"

echo "Keycloak HTTPS Configuration"
echo "===================================="
echo "Keycloak URL: $KEYCLOAK_URL"
echo ""

# Get Keycloak admin password from Secrets Manager
echo "Retrieving Keycloak admin password from AWS Secrets Manager..."
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI not found. Please install it first."
    exit 1
fi

ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id mcp-gateway-keycloak-admin-password-2025111319592408170000000d \
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

python3 << 'PYTHON_EOF'
import requests
import json
import sys
import os
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL', 'https://kc.mycorp.click')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', '')
ADMIN_USER = 'admin'

print(f"Connecting to Keycloak at: {KEYCLOAK_URL}")
print(f"Admin user: {ADMIN_USER}\n")

# Get token
print("Getting admin token...")
try:
    token_resp = requests.post(
        f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token",
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
except Exception as e:
    print(f"ERROR: Failed to connect to Keycloak: {e}")
    sys.exit(1)

if token_resp.status_code != 200:
    print(f"ERROR: Token request failed with status {token_resp.status_code}")
    print(token_resp.text)
    sys.exit(1)

TOKEN = token_resp.json()["access_token"]
print(f"Token obtained successfully\n")

# Get the security-admin-console client
print("Getting security-admin-console client...")
clients_resp = requests.get(
    f"{KEYCLOAK_URL}/admin/realms/master/clients?clientId=security-admin-console",
    headers={"Authorization": f"Bearer {TOKEN}"},
    verify=False,
    timeout=10
)

if clients_resp.status_code == 401:
    print("\nERROR: Admin user does not have permission to access admin API")
    print("The admin token appears valid but doesn't have admin console permissions.")
    print("\nPossible solutions:")
    print("1. Ensure you are using the correct admin password")
    print("2. Try accessing the Keycloak admin console manually and configure it there")
    print("3. Wait for Keycloak to fully initialize (5+ minutes)")
    sys.exit(1)

elif clients_resp.status_code != 200:
    print(f"ERROR: Failed to get clients: {clients_resp.status_code}")
    print(clients_resp.text)
    sys.exit(1)

clients = clients_resp.json()
if not clients:
    print("ERROR: security-admin-console client not found")
    sys.exit(1)

client = clients[0]
client_id = client["id"]
print(f"Found client: {client_id}\n")

print("Current redirect URIs:")
for uri in client.get("redirectUris", []):
    print(f"  - {uri}")

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

client["redirectUris"] = new_redirect_uris

# Send update
print("\nUpdating client...")
update_resp = requests.put(
    f"{KEYCLOAK_URL}/admin/realms/master/clients/{client_id}",
    headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json"
    },
    json=client,
    verify=False,
    timeout=10
)

if update_resp.status_code != 204:
    print(f"ERROR: Failed to update client: {update_resp.status_code}")
    print(update_resp.text)
    sys.exit(1)

print("Client updated successfully!\n")

print("Updated redirect URIs:")
for uri in new_redirect_uris:
    print(f"  - {uri}")

print("\nSuccess! The security-admin-console client has been configured.")
print(f"You can now access the admin console at: {KEYCLOAK_URL}/admin/master/console/")

PYTHON_EOF
