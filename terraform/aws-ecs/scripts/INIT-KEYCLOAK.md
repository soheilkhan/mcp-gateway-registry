# Keycloak Initialization Script

This script initializes Keycloak with the MCP Gateway realm, users, groups, and OAuth2 clients.

## What It Does

The script automatically creates:

1. **Realm**: `mcp-gateway`
2. **Users**:
   - `admin` - realm admin with full access
   - `testuser` - test user with standard permissions
   - `service-account-mcp-gateway-m2m` - service account for M2M authentication

3. **Groups**:
   - `mcp-registry-admin` - Registry administrators
   - `mcp-registry-user` - Registry users
   - `mcp-registry-developer` - Registry developers
   - `mcp-registry-operator` - Registry operators
   - `mcp-servers-unrestricted` - Access to unrestricted MCP servers
   - `mcp-servers-restricted` - Access to restricted MCP servers
   - `a2a-agent-admin` - A2A agent administrators
   - `a2a-agent-publisher` - A2A agent publishers
   - `a2a-agent-user` - A2A agent users

4. **OAuth2 Clients**:
   - `mcp-gateway-web` - Web application client
   - `mcp-gateway-m2m` - Machine-to-machine client

5. **Scopes**: Custom MCP scopes for fine-grained access control

## Prerequisites

- Keycloak must be running and accessible
- `curl` and `jq` must be installed
- Keycloak admin credentials must be available

## Usage

### Option 1: Automatic (Recommended)

If you've already run `save-terraform-outputs.sh`, the script will automatically load the ALB DNS names from the JSON file:

```bash
# First, save terraform outputs
./save-terraform-outputs.sh

# Then run init-keycloak with just the required variables
export KEYCLOAK_ADMIN_URL="https://kc.mycorp.click"
export KEYCLOAK_ADMIN="admin"
export KEYCLOAK_ADMIN_PASSWORD="Keycloak@123456!"

./init-keycloak.sh
```

The script will automatically extract `AUTH_SERVER_EXTERNAL_URL` and `REGISTRY_URL` from `terraform-outputs.json`.

### Option 2: Environment Variables

```bash
export KEYCLOAK_ADMIN_URL="https://kc.mycorp.click"
export KEYCLOAK_ADMIN="admin"
export KEYCLOAK_ADMIN_PASSWORD="Keycloak@123456!"
export AUTH_SERVER_EXTERNAL_URL="http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com:8888"
export REGISTRY_URL="http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com"

./init-keycloak.sh
```

### Option 2: Command Line

```bash
KEYCLOAK_ADMIN_URL="https://kc.mycorp.click" \
KEYCLOAK_ADMIN="admin" \
KEYCLOAK_ADMIN_PASSWORD="Keycloak@123456!" \
AUTH_SERVER_EXTERNAL_URL="http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com:8888" \
REGISTRY_URL="http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com" \
./init-keycloak.sh
```

### Option 3: .env File

Create a `.env` file in the project root:

```bash
# .env
KEYCLOAK_ADMIN_URL=https://kc.mycorp.click
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=Keycloak@123456!
AUTH_SERVER_EXTERNAL_URL=http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com:8888
REGISTRY_URL=http://mcp-gateway-alb-2096799898.us-west-2.elb.amazonaws.com
```

Then run:

```bash
./init-keycloak.sh
```

## Getting ALB DNS Names

To find your ALB DNS names, run:

```bash
# From the terraform directory
cd terraform/aws-ecs

# Get all outputs
terraform output -json | jq '.[] | select(.value | type == "string") | .value' | grep -E "alb|dns|url"

# Or get specific values
terraform output mcp_gateway_alb_dns
terraform output mcp_gateway_auth_url
terraform output mcp_gateway_url
```

## Default Credentials

After running the script, the following users are created:

- **admin**: `admin` / `Keycloak@123456!` (can be overridden with `INITIAL_ADMIN_PASSWORD`)
- **testuser**: `testuser` / `testpass` (can be overridden with `INITIAL_USER_PASSWORD`)

## Retrieving Client Credentials

After initialization, client secrets are generated. To retrieve them:

```bash
# Web client secret
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://kc.mycorp.click/admin/realms/mcp-gateway/clients?clientId=mcp-gateway-web" | jq

# M2M client secret
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://kc.mycorp.click/admin/realms/mcp-gateway/clients?clientId=mcp-gateway-m2m" | jq
```

## Verification

After running the script successfully, you should see output like:

```
Keycloak initialization complete!

You can now access Keycloak at: https://kc.mycorp.click
Admin console: https://kc.mycorp.click/admin
Realm: mcp-gateway

Users created:
  - admin/Keycloak@123456! (realm admin - all groups)
  - testuser/testpass (test user - user/developer/operator groups)
  - service-account-mcp-gateway-m2m (service account for M2M access)

Groups created:
  - mcp-registry-admin, mcp-registry-user, mcp-registry-developer
  - mcp-registry-operator, mcp-servers-unrestricted, mcp-servers-restricted
  - a2a-agent-admin, a2a-agent-publisher, a2a-agent-user

OAuth2 Clients:
  - mcp-gateway-web (for UI authentication)
  - mcp-gateway-m2m (for service-to-service authentication)
```

## Troubleshooting

### "Keycloak did not become ready within 5 minutes"
- Check that Keycloak is running: `curl https://kc.mycorp.click/admin`
- Verify the URL is correct in `KEYCLOAK_ADMIN_URL`

### "Error: Failed to authenticate with Keycloak"
- Verify `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` are correct
- Check that the admin user exists in Keycloak

### "Could not find mcp-gateway-web client"
- The client creation might have failed
- Check the logs in Keycloak admin console
- Try running the script again (it's idempotent and safe to re-run)

## Re-running the Script

The script is idempotent - it's safe to run multiple times. It will:
- Skip realm creation if it already exists
- Skip client creation (will be duplicated if re-run, so use with caution)
- Skip group creation if groups already exist
- Skip user creation if users already exist

## Related Files

- **View Keycloak Logs**: `./view-cloudwatch-logs.sh --component keycloak`
- **Terraform Outputs**: `terraform output` (from `terraform/aws-ecs/`)
- **Main Deployment**: `terraform/aws-ecs/keycloak-ecs.tf`
