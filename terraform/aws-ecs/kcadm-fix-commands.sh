#!/bin/bash
# kcadm.sh commands to fix security-admin-console client
# These commands should be run INSIDE the Keycloak container

# Get the admin password
ADMIN_PASSWORD="oX3eyxv-aTqn0pw-YYz*Js]sbjya{{#3"

echo "Keycloak kcadm.sh Fix Commands"
echo "======================================================================"
echo ""
echo "Run these commands INSIDE the Keycloak container:"
echo ""

cat << 'EOF'
# Step 1: Configure kcadm.sh with admin credentials
/opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user admin \
    --password 'oX3eyxv-aTqn0pw-YYz*Js]sbjya{{#3'

# Step 2: Get current client configuration
echo ""
echo "Current configuration:"
/opt/keycloak/bin/kcadm.sh get clients/d5c54f23-77e9-4123-91d3-b8d25ae8e40b -r master \
    | grep -E '"publicClient"|"clientAuthenticatorType"|"standardFlowEnabled"'

# Step 3: Update client to be public (remove client secret auth)
echo ""
echo "Updating client..."
/opt/keycloak/bin/kcadm.sh update clients/d5c54f23-77e9-4123-91d3-b8d25ae8e40b -r master \
    -s 'publicClient=true' \
    -s 'clientAuthenticatorType=' \
    -s 'standardFlowEnabled=true' \
    -s 'directAccessGrantsEnabled=true' \
    -s 'implicitFlowEnabled=false'

# Step 4: Verify the update
echo ""
echo "Verification:"
/opt/keycloak/bin/kcadm.sh get clients/d5c54f23-77e9-4123-91d3-b8d25ae8e40b -r master \
    | grep -E '"publicClient"|"clientAuthenticatorType"|"standardFlowEnabled"'

echo ""
echo "Done! Now try logging into the admin console:"
echo "https://kc.mycorp.click/admin/master/console/"
EOF

echo ""
echo "======================================================================"
echo ""
echo "To run these commands, you need to:"
echo "1. Enable execute-command on the ECS service (requires Terraform update)"
echo "   OR"
echo "2. Use docker exec if you have direct access to the container"
echo "   OR"
echo "3. Manually configure via the Keycloak admin UI (if you can access it)"
