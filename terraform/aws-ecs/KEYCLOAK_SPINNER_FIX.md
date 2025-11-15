# Keycloak Admin Console Spinner Issue - Root Cause and Fix

## Problem
When accessing `https://kc.mycorp.click/admin/master/console/`, the admin console shows an infinite spinner and never loads.

## Root Causes Identified

### 1. Port 443 in URLs (CORS Issue) - FIXED ✅
**Problem**: `KC_HOSTNAME_PORT="443"` environment variable caused Keycloak to include `:443` in all URLs.
- URLs returned: `https://kc.mycorp.click:443/...`
- Browser origin: `https://kc.mycorp.click`
- Result: **CORS origin mismatch** - browser blocks API calls

**Fix**: Removed `KC_HOSTNAME_PORT` from Terraform configuration
- File: `terraform/aws-ecs/modules/mcp-gateway/ecs-services.tf`
- Removed lines setting `KC_HOSTNAME_PORT = "443"`
- Now URLs are: `https://kc.mycorp.click/...` (no port)

**Verification**:
```bash
curl -s https://kc.mycorp.click/realms/master/.well-known/openid-configuration | grep issuer
# Should show: "issuer": "https://kc.mycorp.click/realms/master" (no :443)
```

### 2. Missing webOrigins Configuration - FIXED ✅
**Problem**: The `security-admin-console` client had no `webOrigins` configured, blocking CORS requests.

**Fix**: Added webOrigins to allow cross-origin requests
- Script: `terraform/aws-ecs/init-keycloak-https.sh`
- Added: `webOrigins: ["+", "https://kc.mycorp.click", ...]`
- The `"+"` means "allow all origins from redirectUris"

**Current Configuration**:
- 5 web origins configured
- Includes both custom domain and ALB URLs

### 3. Client Authentication Conflict - IN PROGRESS ⚠️
**Problem**: `security-admin-console` client has conflicting settings:
- `publicClient: true` (correct - admin console is public)
- `clientAuthenticatorType: "client-secret"` (WRONG - conflicts with public client)

**Error in logs**:
```
type="CODE_TO_TOKEN_ERROR"
error="invalid_code"
client_auth_method="client-secret"
```

**Attempted Fixes**:
1. Set `clientAuthenticatorType = ""` (empty string) - didn't work
2. Delete `clientAuthenticatorType` field - got 401 Unauthorized on PUT

**Current Status**:
- Can GET client configuration (read works)
- Cannot PUT client configuration (write fails with 401)
- Admin user appears to lack permissions to modify master realm clients

## Workarounds to Try

### Option 1: Access via ALB URL
Try accessing the admin console via the ALB URL directly:
```
https://mcp-gateway-kc-alb-948954215.us-east-1.elb.amazonaws.com/admin/master/console/
```

This bypasses custom domain DNS and uses the ALB's direct URL.

### Option 2: Manual Configuration via Browser
If you can access the Keycloak admin console (via ALB URL or otherwise):

1. Login as admin
2. Go to: `Master` realm → `Clients` → `security-admin-console`
3. Settings tab:
   - `Access Type`: public
   - `Standard Flow Enabled`: ON
   - `Direct Access Grants Enabled`: ON
   - `Implicit Flow Enabled`: OFF
4. In "Web Origins": Add `+` (plus symbol)
5. Save

### Option 3: Use Keycloak Setup Script
The `keycloak/setup/init-keycloak.sh` script successfully creates clients with proper configuration.
Consider adapting it to configure the master realm's `security-admin-console` client.

## Files Modified

1. `terraform/aws-ecs/modules/mcp-gateway/ecs-services.tf`
   - Removed `KC_HOSTNAME_PORT = "443"` environment variable

2. `terraform/aws-ecs/init-keycloak-https.sh`
   - Added webOrigins configuration
   - Added code to set publicClient = true
   - Attempted to remove clientAuthenticatorType (partial success)

## Verification Steps

### Check URLs have no :443
```bash
curl -s https://kc.mycorp.click/realms/master/.well-known/openid-configuration \
  | python3 -m json.tool | grep -E "issuer|token_endpoint"
```
Expected: No `:443` in any URLs

### Check Client Configuration
```bash
cd terraform/aws-ecs
source ../.venv/bin/activate
./init-keycloak-https.sh
```

Should show:
- webOrigins: 5 configured
- publicClient: True
- clientAuthenticatorType: should be empty or removed

### Check Logs for Errors
```bash
./get-ecs-logs.sh keycloak-logs --tail 50 | grep -E "ERROR|WARN.*LOGIN"
```

Look for:
- `CODE_TO_TOKEN_ERROR` - OAuth flow failing
- `invalid_code` - authorization code exchange failing
- `client_auth_method="client-secret"` - client still using secret auth

## Next Steps

1. Try ALB URL access (bypasses custom domain issues)
2. If that works, manually configure the client via admin console UI
3. Consider using Terraform Keycloak provider to manage client configuration
4. Alternative: Set up fresh Keycloak with init script and migrate configuration

## Related Files
- `terraform/aws-ecs/init-keycloak-https.sh` - Client configuration script
- `terraform/aws-ecs/modules/mcp-gateway/ecs-services.tf` - Keycloak environment variables
- `keycloak/setup/init-keycloak.sh` - Working setup script for reference
- `terraform/aws-ecs/get-ecs-logs.sh` - Log viewing script

## Lessons Learned

1. **Never set `KC_HOSTNAME_PORT` for standard HTTPS (port 443)**
   - Causes CORS issues due to explicit port in URLs
   - Browser treats `https://host` and `https://host:443` as different origins

2. **Public clients must not have `clientAuthenticatorType`**
   - Setting `publicClient: true` is not enough
   - Must also remove/clear `clientAuthenticatorType` field

3. **webOrigins is critical for SPA applications**
   - Admin console is a Single Page Application (JavaScript)
   - Needs webOrigins configured to make API calls
   - Use `"+"` wildcard to allow all redirectUri origins

4. **Admin API permissions can be tricky**
   - Even admin user may not have full permissions on master realm
   - Direct container access or manual UI configuration may be needed
