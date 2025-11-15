#!/bin/bash
# Fix security-admin-console client configuration for Keycloak behind ALB
# This script updates the client to work properly as a public client

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get admin password
ADMIN_PASSWORD=$(cat /home/ubuntu/repos/mcp-gateway-registry/terraform/.admin_password)

KEYCLOAK_URL="https://kc.mycorp.click"
CLIENT_ID="d5c54f23-77e9-4123-91d3-b8d25ae8e40b"

echo "Keycloak Client Fixer"
echo "=" | head -c 70
echo ""
echo "Target: $KEYCLOAK_URL"
echo "Client ID: $CLIENT_ID"
echo ""

# Use Python to make the API calls
python3 << PYTHON_EOF
import requests
import json
import os
from urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

KEYCLOAK_URL = "$KEYCLOAK_URL"
ADMIN_PASSWORD = "$ADMIN_PASSWORD"
CLIENT_UUID = "$CLIENT_ID"

print("Step 1: Getting admin token...")
token_resp = requests.post(
    f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token",
    data={
        "username": "admin",
        "password": ADMIN_PASSWORD,
        "grant_type": "password",
        "client_id": "admin-cli"
    },
    verify=False,
    timeout=10
)

if token_resp.status_code != 200:
    print(f"ERROR: Failed to get token: {token_resp.status_code}")
    print(token_resp.text)
    exit(1)

TOKEN = token_resp.json()["access_token"]
print("✓ Got admin token")
print()

print("Step 2: Updating specific client fields...")
# Try to update just the problematic fields using JSON patch approach
update_data = {
    "publicClient": True,
    "clientAuthenticatorType": None,  # Set to null to remove
    "standardFlowEnabled": True,
    "directAccessGrantsEnabled": True
}

print(f"  Sending: {json.dumps(update_data, indent=2)}")
print()

update_resp = requests.put(
    f"{KEYCLOAK_URL}/admin/realms/master/clients/{CLIENT_UUID}",
    headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json"
    },
    json=update_data,
    verify=False,
    timeout=10
)

print(f"Response: {update_resp.status_code}")
if update_resp.status_code == 204:
    print("✓ SUCCESS! Client updated")
elif update_resp.status_code == 401:
    print("✗ ERROR: 401 Unauthorized - Admin user lacks permissions")
    print()
    print("This means the admin user cannot modify the master realm's")
    print("security-admin-console client via REST API.")
    print()
    print("WORKAROUND: We need to use kcadm.sh directly in the container.")
else:
    print(f"✗ ERROR: {update_resp.status_code}")
    print(update_resp.text)

PYTHON_EOF

echo ""
echo "If you got 401 Unauthorized, we need to use kcadm.sh instead."
echo "Run: ./run-kcadm-fix.sh"
