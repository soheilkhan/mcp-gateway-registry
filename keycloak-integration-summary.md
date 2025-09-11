# Keycloak Integration Summary

**Date**: 2025-09-11  
**Status**: ✅ COMPLETE - Keycloak authentication working with only X-Authorization header

## Overview

Successfully implemented complete Keycloak integration for MCP Gateway authentication, requiring only the `X-Authorization` header (no additional headers like Cognito needs).

## What Was Accomplished

### 1. Authentication Provider Integration
- ✅ Keycloak provider validates JWT tokens using JWKS
- ✅ Auth server automatically detects Keycloak vs Cognito tokens
- ✅ Only requires `X-Authorization: Bearer <token>` header
- ✅ No need for `X-User-Pool-Id`, `X-Client-Id`, `X-Region` headers

### 2. Group-to-Scope Mapping Fixed
- ✅ Renamed `map_cognito_groups_to_scopes` → `map_groups_to_scopes` (generic for all IDPs)
- ✅ Added Keycloak group mapping logic in auth server
- ✅ Added missing `mcp-servers-unrestricted` group mapping in scopes.yml

### 3. Service Account Setup
- ✅ Created service account user: `service-account-mcp-gateway-m2m`
- ✅ Assigned to group: `mcp-servers-unrestricted`
- ✅ Added groups mapper to M2M client for JWT claims
- ✅ Groups properly appear in JWT tokens

### 4. MCP Protocol Implementation
- ✅ Fixed HTTP Accept headers: `application/json, text/event-stream`
- ✅ Implemented proper MCP session management
- ✅ Added required `notifications/initialized` handshake step
- ✅ Full MCP protocol working end-to-end

## Test Results

The test script `/home/ubuntu/repos/mcp-gateway-registry/test-keycloak-mcp.sh` shows:

```
✅ Test 1: Basic authentication - SUCCESS
✅ Test 2: MCP Initialize - SUCCESS (with session ID)
✅ Test 3: MCP Ping - SUCCESS
✅ Test 4: MCP Tools List - SUCCESS (returns actual tools)
```

## Key Files Modified

### Auth Server Changes
- `auth_server/server.py`: Added Keycloak group-to-scope mapping logic
- `auth_server/scopes.yml`: Added `mcp-servers-unrestricted` group mapping
- `auth_server/providers/keycloak.py`: Working JWT validation

### Keycloak Setup Scripts
- `keycloak/setup/init-keycloak.sh`: Modified to skip existing realm, create service account
- `keycloak/setup/create-service-account-only.sh`: Creates service account user
- `keycloak/setup/add-groups-mapper-m2m.sh`: Adds groups mapper to M2M client

### Test Scripts
- `test-keycloak-mcp.sh`: Complete MCP protocol test with proper session management
- `mcp_cmds.sh`: Updated to detect Keycloak tokens and skip Cognito headers

## Technical Details

### JWT Token Structure
The Keycloak M2M token contains:
```json
{
  "groups": ["mcp-servers-unrestricted"],
  "preferred_username": "service-account-mcp-gateway-m2m",
  "client_id": "mcp-gateway-m2m",
  "scope": "email profile"
}
```

### Group Mappings in scopes.yml
```yaml
group_mappings:
  mcp-servers-unrestricted:
  - mcp-servers-unrestricted/read
  - mcp-servers-unrestricted/execute
```

### Auth Server Logic
1. Keycloak provider validates JWT token
2. Extracts `groups` from JWT claims
3. Maps groups to scopes using `map_groups_to_scopes()` function
4. Validates access based on mapped scopes

### MCP Protocol Flow
1. Initialize request → returns session ID in headers
2. Send `notifications/initialized` with session ID
3. All subsequent requests use session ID header: `mcp-session-id: <id>`

## Environment Setup

### Keycloak Configuration
- **Realm**: `mcp-gateway`
- **M2M Client**: `mcp-gateway-m2m`
- **Service Account**: `service-account-mcp-gateway-m2m`
- **Group**: `mcp-servers-unrestricted`
- **Groups Mapper**: Added to include groups in JWT tokens

### Token Management
- Tokens stored in: `.oauth-tokens/ingress.json`
- Refresh using: `python credentials-provider/token_refresher.py`
- Token duration: 5 minutes (300 seconds)

## Current Issues Resolved

### ✅ Fixed Issues
1. **Group mapping not working** → Added Keycloak group-to-scope mapping
2. **Service account missing** → Created service account user
3. **Groups not in JWT** → Added groups mapper to M2M client
4. **MCP protocol errors** → Fixed headers and session management
5. **Function naming confusion** → Renamed to generic `map_groups_to_scopes`

## Keycloak Client and Secret Generation

### How the M2M Client was Created
The Keycloak M2M client and secret were generated through the Keycloak admin console or via the `init-keycloak.sh` script:

1. **Client Creation Process**:
   ```bash
   # In init-keycloak.sh, the M2M client is created with:
   CLIENT_JSON='{
       "clientId": "mcp-gateway-m2m",
       "enabled": true,
       "clientAuthenticatorType": "client-secret",
       "serviceAccountsEnabled": true,
       "standardFlowEnabled": false,
       "implicitFlowEnabled": false,
       "directAccessGrantsEnabled": false
   }'
   ```

2. **Secret Generation**:
   - Keycloak automatically generates a client secret when the client is created
   - The secret can be retrieved from: Admin Console → Clients → mcp-gateway-m2m → Credentials tab
   - Or via API: `GET /admin/realms/{realm}/clients/{client-id}/client-secret`

3. **Current Configuration**:
   - **Client ID**: `mcp-gateway-m2m` 
   - **Client Secret**: Generated by Keycloak (stored in environment variables)
   - **Grant Type**: `client_credentials` (for M2M authentication)
   - **Service Accounts**: Enabled

### Service Account Architecture - Individual Agent Audit Trails

**Recommendation: ONE service account per AI agent for proper audit trails**

#### Production Architecture (Recommended):
```
AI Agent A → Service Account A (agent-{agent-id}-m2m) → Group: mcp-servers-restricted/unrestricted
AI Agent B → Service Account B (agent-{agent-id}-m2m) → Group: mcp-servers-restricted/unrestricted  
AI Agent C → Service Account C (agent-{agent-id}-m2m) → Group: mcp-servers-restricted/unrestricted
                                      ↓
                              Individual JWT Tokens per Agent
                                      ↓
                              Group-based Authorization + Individual Tracking
```

#### Why Individual Service Accounts are Essential:

1. **Audit Trail Requirements**:
   - Each agent's actions are individually traceable
   - Security incidents can be traced to specific agents
   - Compliance requirements for user activity logging
   - Performance monitoring per agent

2. **Security Isolation**:
   - Compromised agent doesn't affect other agents
   - Individual token revocation capability
   - Granular access control per agent
   - Risk containment

3. **Operational Benefits**:
   - Per-agent metrics and monitoring
   - Individual rate limiting and throttling
   - Agent-specific debugging and troubleshooting
   - Clearer responsibility boundaries

4. **Compliance and Governance**:
   - Required for SOC2, ISO27001, and similar frameworks
   - Individual accountability for AI agent actions
   - Detailed audit logs for regulatory requirements

#### Service Account Naming Convention:
```
Pattern: agent-{agent-id}-m2m
Examples:
- agent-claude-001-m2m
- agent-bedrock-claude-m2m  
- agent-gpt4-turbo-m2m
- agent-gemini-pro-m2m
```

#### Legacy Single Account (Development Only):
```
Development/Testing → Single Service Account (mcp-gateway-m2m) → Group: mcp-servers-unrestricted
```
**Use single account only for**:
- Development and testing environments
- Proof of concept implementations
- Non-production workloads

### Current Setup Details

#### Production Architecture (Recommended)
- **Service Account Pattern**: `agent-{agent-id}-m2m`
- **Example Accounts**: 
  - `agent-claude-001-m2m` → `mcp-servers-unrestricted`
  - `agent-gpt4-turbo-m2m` → `mcp-servers-restricted`
  - `agent-bedrock-claude-m2m` → `mcp-servers-unrestricted`
- **Token Storage**: `.oauth-tokens/agent-{agent-id}.json`
- **Audit Trail**: Individual tracking per agent

#### Development Setup (Legacy)
- **Service Account**: `service-account-mcp-gateway-m2m`
- **Group Assignment**: `mcp-servers-unrestricted` 
- **Token Storage**: `.oauth-tokens/ingress.json`
- **Audit Trail**: Single shared identity

#### Scope Mapping (Both Architectures)
- `mcp-servers-unrestricted/read` + `mcp-servers-unrestricted/execute`
- `mcp-servers-restricted/read` + `mcp-servers-restricted/execute`

## Next Steps / TODO

### 1. Consolidate Service Account Setup ✅ COMPLETED
- ✅ Created single script: `keycloak/setup/setup-m2m-service-account.sh`
- ✅ Combines service account creation, group assignment, and groups mapper setup

### 2. Documentation
- [ ] Update README with Keycloak setup instructions
- [ ] Document the complete authentication flow

### 3. Optional Improvements
- [ ] Add error handling for expired tokens in test script
- [ ] Consider automating token refresh in test scenarios
- [ ] Add more comprehensive MCP protocol tests

## Commands to Resume Work

### Setup From Scratch (New Installation)

#### Production Setup (Individual Agent Accounts)
```bash
# 1. Start Keycloak and run basic initialization
docker-compose up -d keycloak
./keycloak/setup/init-keycloak.sh

# 2. Create agent-specific service accounts
./keycloak/setup/setup-agent-service-account.sh --agent-id claude-001 --group mcp-servers-unrestricted
./keycloak/setup/setup-agent-service-account.sh --agent-id gpt4-turbo --group mcp-servers-restricted
./keycloak/setup/setup-agent-service-account.sh --agent-id bedrock-claude --group mcp-servers-unrestricted

# 3. Generate agent-specific M2M tokens
python credentials-provider/token_refresher.py --agent-id claude-001
python credentials-provider/token_refresher.py --agent-id gpt4-turbo

# 4. Test agent-specific authentication
./test-keycloak-mcp.sh --agent-id claude-001
./test-keycloak-mcp.sh --agent-id gpt4-turbo
```

#### Development Setup (Single Account)
```bash
# 1. Start Keycloak and run basic initialization
docker-compose up -d keycloak
./keycloak/setup/init-keycloak.sh

# 2. Run the consolidated M2M setup script (legacy)
./keycloak/setup/setup-m2m-service-account.sh

# 3. Generate M2M token
python credentials-provider/token_refresher.py

# 4. Test the integration
./test-keycloak-mcp.sh
```

### Test Current Setup
```bash
# Generate fresh token
python credentials-provider/token_refresher.py

# Test complete MCP protocol
./test-keycloak-mcp.sh

# Check auth server logs
docker-compose logs auth-server | tail -20
```

### Using the Agent-Specific Setup Script (Production)
The new script `keycloak/setup/setup-agent-service-account.sh` handles:
- ✅ Agent-specific service account creation (`agent-{id}-m2m`)
- ✅ Group creation (if needed) 
- ✅ Group assignment (restricted/unrestricted)
- ✅ Groups mapper configuration
- ✅ Agent metadata and attributes
- ✅ Agent-specific token configuration
- ✅ Complete audit trail setup

```bash
# Create service account for Claude agent with full access
./keycloak/setup/setup-agent-service-account.sh --agent-id claude-001 --group mcp-servers-unrestricted

# Create service account for GPT-4 agent with restricted access  
./keycloak/setup/setup-agent-service-account.sh --agent-id gpt4-turbo --group mcp-servers-restricted

# Expected output:
# ✓ Admin token obtained
# ✓ Service account user created successfully
# ✓ Target group 'mcp-servers-unrestricted' exists with ID: xxx
# ✓ Service account assigned to 'mcp-servers-unrestricted' group
# ✓ Found M2M client with ID: xxx
# ✓ Groups mapper added successfully
# ✓ Service account is in 'mcp-servers-unrestricted' group
# ✓ Groups mapper is configured
# ✓ Agent token configuration created: .oauth-tokens/agent-claude-001.json
# SUCCESS! Agent service account setup complete.
```

### Using the Legacy Consolidated Script (Development)
The legacy script `keycloak/setup/setup-m2m-service-account.sh` creates a single shared service account:
- ✅ Single service account creation
- ✅ Group assignment
- ✅ Groups mapper configuration
- ❌ No individual audit trails
- ❌ No agent-specific tracking

**Use only for development/testing environments**

### Rebuild if Changes Made
```bash
docker-compose down
docker-compose up --build -d
```

## File Locations

### Key Configuration Files
- Auth server code: `auth_server/server.py`
- Scopes configuration: `auth_server/scopes.yml` 
- Keycloak provider: `auth_server/providers/keycloak.py`

### Setup Scripts
- Main init: `keycloak/setup/init-keycloak.sh`
- **Agent-specific setup**: `keycloak/setup/setup-agent-service-account.sh` ⭐ (Production)
- Legacy consolidated script: `keycloak/setup/setup-m2m-service-account.sh` (Development)
- Legacy scripts: `keycloak/setup/create-service-account-only.sh`, `keycloak/setup/add-groups-mapper-m2m.sh`

### Test Scripts
- MCP test: `test-keycloak-mcp.sh`
- MCP commands: `mcp_cmds.sh`

### Token Storage
- Current token: `.oauth-tokens/ingress.json`

## Success Criteria Met

✅ **Primary Requirement**: Keycloak authentication works with only `X-Authorization` header  
✅ **Secondary**: Complete MCP protocol implementation  
✅ **Tertiary**: Proper group-based authorization working  

## Architecture Summary

```
User Request → nginx → Auth Server (Keycloak validation) → MCP Gateway → MCP Server
                ↓
            JWT Validation + Group Mapping + Scope Authorization
```

The integration is **production-ready** and requires only the X-Authorization header for Keycloak authentication.