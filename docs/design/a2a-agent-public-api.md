# A2A Agent Public API

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [API Endpoints](#api-endpoints)
4. [Authentication](#authentication)
5. [Data Format](#data-format)
6. [Pagination](#pagination)
7. [Implementation Details](#implementation-details)
8. [Testing](#testing)
9. [Troubleshooting](#troubleshooting)
10. [Migration and Integration](#migration-and-integration)

---

## Overview

The A2A Agent Public API provides a standardized REST interface for discovering and retrieving information about A2A (Agent-to-Agent) agents registered in the MCP Gateway Registry. This API implements the [Anthropic MCP Registry REST API v0.1 specification](https://github.com/modelcontextprotocol/registry), enabling seamless compatibility with the Anthropic AI platform and other downstream consumers.

### What is A2A Agent Public API

The A2A Agent Public API exposes registered A2A agents through three REST endpoints that follow the standard MCP Registry pattern. These endpoints allow authenticated clients to:

- List all available agents with cursor-based pagination
- Discover agents by name and version
- Retrieve detailed agent specifications and capabilities
- Authenticate using JWT Bearer tokens issued by Keycloak

### Why It Exists: Anthropic MCP Registry Compatibility

The A2A Agent Public API was created to provide interoperability with Anthropic's official MCP Registry specification. This enables:

1. **Ecosystem Integration** - A2A agents registered in the gateway become discoverable by Anthropic's ecosystem tools
2. **Standardized Protocol** - Uses the same REST API pattern as other MCP registries
3. **Authentication Flow** - JWT Bearer tokens via Keycloak provide secure, standards-based access control
4. **Data Transformation** - Automatically converts internal agent cards to Anthropic's ServerDetail/ServerResponse schema

### Key Features and Benefits

- **REST API Endpoints** - 3 simple GET endpoints for agent discovery and retrieval
- **JWT Authentication** - Secure authentication using Keycloak-issued Bearer tokens
- **Cursor-Based Pagination** - Efficient pagination for large agent lists
- **Standard Schema** - Compliant with Anthropic MCP Registry OpenAPI specification
- **Namespace Convention** - Reverse-DNS naming (io.mcpgateway/agent-name) for unique agent identification
- **Version Support** - Agents support multiple versions (currently fixed at "1.0.0")
- **Health Status Defaults** - A2A agents default to "healthy" status
- **Metadata Preservation** - Rich metadata including skills, tags, visibility, and trust levels

---

## Architecture

### System Diagram

```
┌────────────────────────────────────────────────────────────────┐
│ Client                                                         │
│ (Authorization: Bearer <JWT>)                                  │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          │ HTTP/S Request
                          │ GET /v0.1/agents
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│ Nginx Reverse Proxy (:80/:443)                                 │
│                                                                │
│ ┌──────────────────────────────────────────────────────┐       │
│ │ Location: /v0.1/*                                   │       │
│ │ ├─ Extract Bearer token from Authorization header   │       │
│ │ └─ Forward auth_request to Auth Server ──┐          │       │
│ └──────────────────────────────────────────┼──────────┘       │
│                                             │                  │
│ ◄──────────────────────────────────────────┘                  │
│                                                                │
│ X-User: {user_context}                                         │
│ X-Scopes: ["scope1", "scope2"]                                │
│ X-Username: "username"                                        │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          │ Proxied Request
                          │ + Auth Headers
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│ Auth Server (:8888)                                            │
│                                                                │
│ ├─ Receives auth_request from Nginx                           │
│ ├─ Extracts JWT from Authorization header                     │
│ ├─ Validates JWT signature and expiration                     │
│ ├─ Checks with Keycloak for user roles/scopes                │
│ └─ Returns X-User, X-Scopes, X-Username headers              │
│    (or 401 if validation fails)                              │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          │ Processed Request
                          │ (with user headers)
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│ Registry FastAPI (:7860)                                       │
│                                                                │
│ ┌──────────────────────────────────────────────────────┐       │
│ │ agent_registry_routes.py                            │       │
│ │ (Anthropic MCP Registry API)                         │       │
│ │                                                      │       │
│ │ ├─ GET /v0.1/agents                                │       │
│ │ │  └─ nginx_proxied_auth() reads headers            │       │
│ │ │     └─ Returns paginated ServerList               │       │
│ │ │                                                   │       │
│ │ ├─ GET /v0.1/agents/{agentName}/versions          │       │
│ │ │  └─ List versions for specific agent              │       │
│ │ │                                                   │       │
│ │ └─ GET /v0.1/agents/{agentName}/versions/{version} │       │
│ │    └─ Get detailed agent specifications             │       │
│ │                                                     │       │
│ │ agent_transform_service.py                          │       │
│ │ ├─ transform_to_agent_list()                        │       │
│ │ ├─ transform_to_agent_response()                    │       │
│ │ └─ transform_to_agent_detail()                      │       │
│ │                                                     │       │
│ │ agent_service.py                                    │       │
│ │ ├─ list_agents() - from file storage                │       │
│ │ ├─ get_agent() - by path lookup                     │       │
│ │ └─ is_agent_enabled() - check enable status         │       │
│ └──────────────────────────────────────────────────────┘       │
│                                                                │
│ Response: ServerList | ServerResponse (Anthropic schema)       │
└────────────────────────────────────────────────────────────────┘
```

### Component Interactions

1. **Client** initiates request with Bearer token in Authorization header
2. **Nginx** intercepts request, extracts token, calls Auth Server for validation
3. **Auth Server** validates JWT, checks Keycloak, returns user context headers
4. **FastAPI** receives request with X-User, X-Scopes, X-Username headers
5. **nginx_proxied_auth()** dependency extracts and validates headers
6. **agent_registry_routes.py** handles request, calls agent_service for data
7. **agent_transform_service.py** converts internal format to Anthropic schema
8. **Response** returned as ServerList or ServerResponse (Anthropic format)

### Authentication Flow

```
Client Request
    │
    ├─ Has "Authorization: Bearer <JWT>" header
    │
    ▼
Nginx Receives Request
    │
    ├─ Forwards to Auth Server for validation
    │
    ▼
Auth Server
    │
    ├─ Extract JWT from header
    ├─ Verify signature (using Keycloak public key)
    ├─ Check expiration time
    ├─ Validate scopes against request
    │
    ├─ If valid:
    │  └─ Return 200 with X-User, X-Scopes, X-Username
    │
    └─ If invalid:
       └─ Return 401 Unauthorized
          Nginx blocks request
          Client receives 401
```

### Data Transformation Pipeline

```
Agent Storage (JSON Files)
    │
    ├─ Internal AgentCard format
    │  {
    │    "path": "/agents/code-reviewer",
    │    "name": "Code Reviewer",
    │    "description": "...",
    │    "url": "https://...",
    │    "protocol_version": "1.0",
    │    "skills": [...],
    │    "tags": [...],
    │    "visibility": "public",
    │    ...
    │  }
    │
    ▼
agent_service.list_agents() / get_agent()
    │
    ├─ Load from storage
    ├─ Filter by enabled status
    ├─ Add metadata (health_status, is_enabled)
    │
    ▼
agent_transform_service.py
    │
    ├─ transform_to_agent_list()
    │  └─ Convert to ServerList (for /agents endpoint)
    │
    ├─ transform_to_agent_response()
    │  └─ Convert to ServerResponse (for /versions/{version} endpoint)
    │
    └─ Internal transforms:
       ├─ _create_agent_name() - "io.mcpgateway/code-reviewer"
       ├─ _determine_agent_version() - "1.0.0"
       ├─ _create_agent_transport_config() - HTTP transport
       │
       ▼
Anthropic Schema
    │
    ├─ ServerResponse
    │  {
    │    "server": {
    │      "name": "io.mcpgateway/code-reviewer",
    │      "description": "...",
    │      "version": "1.0.0",
    │      "packages": [{
    │        "registryType": "mcpb",
    │        "identifier": "io.mcpgateway/code-reviewer",
    │        "version": "1.0.0",
    │        "transport": {
    │          "type": "streamable-http",
    │          "url": "https://..."
    │        }
    │      }],
    │      "meta": {...}
    │    }
    │  }
    │
    └─ ServerList
       {
         "servers": [ServerResponse, ...],
         "metadata": {
           "count": 10,
           "nextCursor": "io.mcpgateway/next-agent"
         }
       }
```

---

## API Endpoints

All endpoints are located at `/{ANTHROPIC_API_VERSION}/agents` where `ANTHROPIC_API_VERSION` defaults to `v0.1`.

### 1. List Agents

List all registered A2A agents with cursor-based pagination.

#### Request

```http
GET /v0.1/agents?cursor=&limit=100 HTTP/1.1
Host: registry.example.com
Authorization: Bearer <JWT>
```

#### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `cursor` | string | No | null | Pagination cursor from previous response. Opaque string representing the agent name to start after. |
| `limit` | integer | No | 100 | Maximum results per page. Must be between 1 and 1000. |

#### Request Headers

| Header | Value | Description |
|--------|-------|-------------|
| `Authorization` | Bearer <JWT> | JWT token issued by Keycloak. Required. |

#### Response

```json
{
  "servers": [
    {
      "server": {
        "name": "io.mcpgateway/code-reviewer",
        "description": "AI-powered code review agent",
        "version": "1.0.0",
        "title": "Code Reviewer Agent",
        "packages": [
          {
            "registryType": "mcpb",
            "identifier": "io.mcpgateway/code-reviewer",
            "version": "1.0.0",
            "transport": {
              "type": "streamable-http",
              "url": "https://code-reviewer.example.com/api"
            },
            "runtimeHint": "docker"
          }
        ],
        "meta": {
          "io.mcpgateway/internal": {
            "path": "/code-reviewer",
            "type": "a2a-agent",
            "is_enabled": true,
            "visibility": "public",
            "trust_level": "verified",
            "skills": [],
            "tags": ["code-review", "ai"],
            "protocol_version": "1.0"
          }
        }
      },
      "meta": {
        "io.mcpgateway/registry": {
          "last_checked": null,
          "health_status": "healthy"
        }
      }
    }
  ],
  "metadata": {
    "count": 1,
    "nextCursor": null
  }
}
```

#### Status Codes

| Code | Description | Example |
|------|-------------|---------|
| 200 | Success. Returns list of agents. | OK |
| 400 | Bad request. Invalid parameters. | limit > 1000 |
| 401 | Unauthorized. Missing or invalid JWT. | Invalid token signature |
| 403 | Forbidden. User lacks required scopes. | User not authorized for agents |
| 500 | Server error. | Internal database error |

#### Example

```bash
# List first 10 agents
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?limit=10"

# Get next page using cursor
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?cursor=io.mcpgateway%2Fagent-10&limit=10"
```

---

### 2. List Agent Versions

List all available versions for a specific agent.

#### Request

```http
GET /v0.1/agents/{agentName}/versions HTTP/1.1
Host: registry.example.com
Authorization: Bearer <JWT>
```

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `agentName` | string | URL-encoded agent name in reverse-DNS format. Example: `io.mcpgateway%2Fcode-reviewer`. The forward slash MUST be URL-encoded as `%2F`. |

#### Request Headers

| Header | Value | Description |
|--------|-------|-------------|
| `Authorization` | Bearer <JWT> | JWT token issued by Keycloak. Required. |

#### Response

```json
{
  "servers": [
    {
      "server": {
        "name": "io.mcpgateway/code-reviewer",
        "description": "AI-powered code review agent",
        "version": "1.0.0",
        "title": "Code Reviewer Agent",
        "packages": [
          {
            "registryType": "mcpb",
            "identifier": "io.mcpgateway/code-reviewer",
            "version": "1.0.0",
            "transport": {
              "type": "streamable-http",
              "url": "https://code-reviewer.example.com/api"
            },
            "runtimeHint": "docker"
          }
        ],
        "meta": {
          "io.mcpgateway/internal": {
            "path": "/code-reviewer",
            "type": "a2a-agent",
            "is_enabled": true,
            "visibility": "public",
            "trust_level": "verified",
            "skills": [],
            "tags": ["code-review", "ai"],
            "protocol_version": "1.0"
          }
        }
      },
      "meta": {
        "io.mcpgateway/registry": {
          "last_checked": null,
          "health_status": "healthy"
        }
      }
    }
  ],
  "metadata": {
    "count": 1,
    "nextCursor": null
  }
}
```

#### Status Codes

| Code | Description |
|------|-------------|
| 200 | Success. Returns list of versions (currently always single version). |
| 401 | Unauthorized. Missing or invalid JWT. |
| 403 | Forbidden. User lacks required scopes. |
| 404 | Not Found. Agent not found or user lacks access. |
| 500 | Server error. |

#### URL Encoding Notes

The agent name must be properly URL-encoded:

```
Internal path: /code-reviewer
Reverse-DNS:  io.mcpgateway/code-reviewer
URL-encoded:  io.mcpgateway%2Fcode-reviewer

Request URL: /v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions
```

#### Example

```bash
# List versions for code-reviewer agent
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions"

# Using Python requests
import requests
agent_name = "io.mcpgateway/code-reviewer"
url = f"https://registry.example.com/v0.1/agents/{agent_name}/versions"
headers = {"Authorization": f"Bearer {token}"}
# requests.get() automatically URL-encodes the URL
response = requests.get(url, headers=headers)
```

---

### 3. Get Agent Version Details

Retrieve detailed specifications for a specific agent version.

#### Request

```http
GET /v0.1/agents/{agentName}/versions/{version} HTTP/1.1
Host: registry.example.com
Authorization: Bearer <JWT>
```

#### Path Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `agentName` | string | URL-encoded agent name (e.g., `io.mcpgateway%2Fcode-reviewer`). |
| `version` | string | Version string. Use `latest` for most recent version. Currently supports: `latest`, protocol version (e.g., `1.0`, `1.0.0`). |

#### Request Headers

| Header | Value | Description |
|--------|-------|-------------|
| `Authorization` | Bearer <JWT> | JWT token issued by Keycloak. Required. |

#### Response

```json
{
  "server": {
    "name": "io.mcpgateway/code-reviewer",
    "description": "AI-powered code review agent that analyzes code and provides feedback",
    "version": "1.0.0",
    "title": "Code Reviewer Agent",
    "repository": null,
    "packages": [
      {
        "registryType": "mcpb",
        "identifier": "io.mcpgateway/code-reviewer",
        "version": "1.0.0",
        "transport": {
          "type": "streamable-http",
          "url": "https://code-reviewer.example.com/api"
        },
        "runtimeHint": "docker"
      }
    ],
    "meta": {
      "io.mcpgateway/internal": {
        "path": "/code-reviewer",
        "type": "a2a-agent",
        "is_enabled": true,
        "visibility": "public",
        "trust_level": "verified",
        "skills": [
          {
            "id": "review-code",
            "name": "Review Code",
            "description": "Analyzes code and provides feedback",
            "parameters": {
              "type": "object",
              "properties": {
                "code": {
                  "type": "string",
                  "description": "Code to review"
                }
              }
            },
            "tags": ["code-analysis"]
          }
        ],
        "tags": ["code-review", "ai", "developer-tools"],
        "protocol_version": "1.0"
      }
    }
  },
  "meta": {
    "io.mcpgateway/registry": {
      "last_checked": null,
      "health_status": "healthy"
    }
  }
}
```

#### Status Codes

| Code | Description |
|------|-------------|
| 200 | Success. Returns full agent details. |
| 401 | Unauthorized. Missing or invalid JWT. |
| 403 | Forbidden. User lacks required scopes. |
| 404 | Not Found. Agent or version not found. |
| 500 | Server error. |

#### Version Resolution

The endpoint supports flexible version matching:

- `latest` - Always returns current version (usually 1.0.0)
- `1.0.0` - Exact protocol version match
- `1.0` - Matches any protocol version starting with 1.0

Invalid versions (e.g., `2.0.0`) return 404 if agent doesn't support them.

#### Example

```bash
# Get latest version
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions/latest"

# Get specific version
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions/1.0.0"

# Pretty print response
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions/latest" | jq .
```

---

## Authentication

### JWT Bearer Token Requirement

All endpoints require authentication using JWT Bearer tokens in the Authorization header:

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Token format:
- **Type**: JWT (JSON Web Token)
- **Source**: Keycloak authentication server
- **Validation**: Signature verified against Keycloak public key
- **Expiration**: Token must not be expired

### Getting Tokens from Keycloak

#### Prerequisites

- Keycloak server configured and running
- User account created in Keycloak
- Realm and client configured for OAuth2/OpenID Connect

#### Token Request Flow

```
User Credentials
    │
    ├─ POST /auth/realms/{realm}/protocol/openid-connect/token
    │  ├─ grant_type: password
    │  ├─ client_id: registry-client
    │  ├─ username: user@example.com
    │  ├─ password: <password>
    │
    ▼
Keycloak
    │
    ├─ Validates credentials
    ├─ Creates JWT with:
    │  ├─ Header: { "alg": "RS256", "typ": "JWT" }
    │  ├─ Payload: { "sub", "username", "scope", "exp", ... }
    │  ├─ Signature: RS256(header.payload, private_key)
    │
    ▼
Response
    │
    ├─ access_token: <JWT>
    ├─ token_type: Bearer
    ├─ expires_in: 3600
    └─ refresh_token: <JWT>
```

#### Example: Get Token Using Keycloak CLI

```bash
# Set variables
KEYCLOAK_URL="https://keycloak.example.com"
REALM="mcp-gateway"
CLIENT_ID="registry-client"
USERNAME="user@example.com"
PASSWORD="password123"

# Request token
TOKEN=$(curl -s -X POST \
  "$KEYCLOAK_URL/auth/realms/$REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  | jq -r '.access_token')

echo "Token: $TOKEN"

# Use token in API request
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents"
```

#### Example: Get Token Using Python

```python
import requests

keycloak_url = "https://keycloak.example.com"
realm = "mcp-gateway"
client_id = "registry-client"
username = "user@example.com"
password = "password123"

token_url = f"{keycloak_url}/auth/realms/{realm}/protocol/openid-connect/token"

response = requests.post(
    token_url,
    data={
        "grant_type": "password",
        "client_id": client_id,
        "username": username,
        "password": password,
    }
)

token = response.json()["access_token"]

# Use token in API request
headers = {"Authorization": f"Bearer {token}"}
api_response = requests.get(
    "https://registry.example.com/v0.1/agents",
    headers=headers
)
```

### Token Expiration Handling

Tokens are time-limited for security. Handle expiration gracefully:

#### Token Structure

```
Header.Payload.Signature

Payload contains:
{
  "exp": 1704067200,  // Unix timestamp (seconds since epoch)
  "iat": 1704063600,  // Issued at
  "expires_in": 3600, // Validity in seconds
  ...
}
```

#### Checking Expiration

```python
import jwt
import time

# Decode token (without verification for inspection only)
decoded = jwt.decode(token, options={"verify_signature": False})
exp_time = decoded["exp"]
current_time = int(time.time())

if current_time > exp_time:
    print("Token expired - request new token")
else:
    time_remaining = exp_time - current_time
    print(f"Token valid for {time_remaining} more seconds")
```

#### Refresh Token Flow

```bash
# When token expires, use refresh token to get new token
curl -X POST \
  "https://keycloak.example.com/auth/realms/mcp-gateway/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=registry-client" \
  -d "refresh_token=$REFRESH_TOKEN" \
  | jq '.access_token'
```

### Error Responses

#### 401 Unauthorized

Returned when:
- Authorization header is missing
- Bearer token format is incorrect
- JWT signature is invalid
- Token is expired
- User does not exist in Keycloak

```json
{
  "detail": "Unauthorized"
}
```

HTTP Status: `401 Unauthorized`

#### 403 Forbidden

Returned when:
- User is authenticated but lacks required scopes
- User cannot access the specific agent (visibility/permission mismatch)

```json
{
  "detail": "Forbidden"
}
```

HTTP Status: `403 Forbidden`

---

## Data Format

### Internal Agent Card Format

Agents are stored in JSON files following the A2A protocol specification:

```json
{
  "protocol_version": "1.0",
  "name": "Code Reviewer",
  "description": "AI-powered code review agent",
  "url": "https://code-reviewer.example.com/api",
  "version": "1.0.0",
  "provider": "Acme Corp",
  "path": "/code-reviewer",
  "tags": ["code-review", "ai", "developer-tools"],
  "visibility": "public",
  "trust_level": "verified",
  "skills": [
    {
      "id": "review-code",
      "name": "Review Code",
      "description": "Analyzes code and provides feedback",
      "parameters": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string",
            "description": "Source code to review"
          },
          "language": {
            "type": "string",
            "description": "Programming language"
          }
        },
        "required": ["code"]
      },
      "tags": ["code-analysis"]
    }
  ],
  "security_schemes": {
    "api_key": {
      "type": "apiKey",
      "in": "header",
      "name": "X-API-Key"
    }
  },
  "streaming": false,
  "is_enabled": true,
  "registered_by": "admin@example.com",
  "registered_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-20T14:45:00Z"
}
```

### Transformed Anthropic Format

When returned via the public API, agents are transformed to Anthropic's ServerDetail/ServerResponse schema:

```json
{
  "server": {
    "name": "io.mcpgateway/code-reviewer",
    "description": "AI-powered code review agent",
    "version": "1.0.0",
    "title": "Code Reviewer",
    "repository": null,
    "packages": [
      {
        "registryType": "mcpb",
        "identifier": "io.mcpgateway/code-reviewer",
        "version": "1.0.0",
        "transport": {
          "type": "streamable-http",
          "url": "https://code-reviewer.example.com/api"
        },
        "runtimeHint": "docker"
      }
    ],
    "meta": {
      "io.mcpgateway/internal": {
        "path": "/code-reviewer",
        "type": "a2a-agent",
        "is_enabled": true,
        "visibility": "public",
        "trust_level": "verified",
        "skills": [...],
        "tags": ["code-review", "ai", "developer-tools"],
        "protocol_version": "1.0"
      }
    }
  },
  "meta": {
    "io.mcpgateway/registry": {
      "last_checked": null,
      "health_status": "healthy"
    }
  }
}
```

### Namespace Convention

A2A agents use reverse-DNS naming for uniqueness:

```
Format: {domain}/{agent-name}

Examples:
  io.mcpgateway/code-reviewer
  io.mcpgateway/data-analyst
  io.mcpgateway/security-auditor
  io.mcpgateway/test-generator

Domain: io.mcpgateway
  ├─ Identifies MCP Gateway Registry as origin
  ├─ Prevents conflicts with other registries
  └─ Follows Java/Go package naming convention

Agent Name: code-reviewer
  ├─ Lowercase, hyphenated
  ├─ Corresponds to internal path: /code-reviewer
  └─ Uniquely identifies agent within gateway
```

### Metadata Structure

The transformed response includes nested metadata at two levels:

#### Level 1: Internal Metadata (`io.mcpgateway/internal`)

Contains MCP Gateway-specific information about the agent:

```json
{
  "io.mcpgateway/internal": {
    "path": "/code-reviewer",              // Internal registry path
    "type": "a2a-agent",                  // Entity type (always "a2a-agent")
    "is_enabled": true,                   // Enabled in registry
    "visibility": "public",               // Access level: public|private|group-restricted
    "trust_level": "verified",            // Trust: unverified|community|verified|trusted
    "skills": [...],                      // Array of skill objects
    "tags": [...],                        // Categorization tags
    "protocol_version": "1.0"             // A2A protocol version
  }
}
```

#### Level 2: Registry Metadata (`io.mcpgateway/registry`)

Contains registry operational information:

```json
{
  "io.mcpgateway/registry": {
    "last_checked": null,                 // Last health check timestamp (ISO 8601 or null)
    "health_status": "healthy"            // Health: healthy|unhealthy|unknown
  }
}
```

---

## Pagination

The API implements cursor-based pagination for efficient handling of large agent lists.

### Cursor-Based Algorithm

Pagination uses opaque cursor strings to maintain consistent ordering:

```
1. Client requests /agents (no cursor, gets first page)
2. Server returns:
   - First N agents (sorted by name)
   - nextCursor = name of (N)th agent
3. Client requests /agents?cursor=nextCursor
4. Server finds cursor agent in sorted list
5. Server returns agents starting AFTER cursor
6. Process repeats until nextCursor is null
```

### Algorithm Implementation

```python
# Pseudocode from agent_transform_service.py

def transform_to_agent_list(agents, cursor=None, limit=100):
    # 1. Sort agents consistently by name
    sorted_agents = sorted(agents, key=lambda a: agent_name(a))

    # 2. Find starting position
    start_index = 0
    if cursor:
        for idx, agent in enumerate(sorted_agents):
            if agent_name(agent) == cursor:
                start_index = idx + 1  # Start AFTER the cursor
                break

    # 3. Slice results
    end_index = start_index + limit
    page_agents = sorted_agents[start_index:end_index]

    # 4. Determine next cursor
    next_cursor = None
    if end_index < len(sorted_agents):
        # More results exist
        next_cursor = agent_name(sorted_agents[end_index - 1])

    # 5. Return ServerList with pagination metadata
    return ServerList(
        servers=transform_agents(page_agents),
        metadata=PaginationMetadata(
            nextCursor=next_cursor,
            count=len(page_agents)
        )
    )
```

### Example Pagination Flow

#### Request 1: Get First Page

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?limit=2"
```

Response:
```json
{
  "servers": [
    {"server": {"name": "io.mcpgateway/agent-a", ...}},
    {"server": {"name": "io.mcpgateway/agent-b", ...}}
  ],
  "metadata": {
    "count": 2,
    "nextCursor": "io.mcpgateway/agent-b"
  }
}
```

#### Request 2: Get Next Page

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?cursor=io.mcpgateway%2Fagent-b&limit=2"
```

Response:
```json
{
  "servers": [
    {"server": {"name": "io.mcpgateway/agent-c", ...}},
    {"server": {"name": "io.mcpgateway/agent-d", ...}}
  ],
  "metadata": {
    "count": 2,
    "nextCursor": "io.mcpgateway/agent-d"
  }
}
```

#### Request 3: Get Last Page

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?cursor=io.mcpgateway%2Fagent-d&limit=2"
```

Response:
```json
{
  "servers": [
    {"server": {"name": "io.mcpgateway/agent-e", ...}}
  ],
  "metadata": {
    "count": 1,
    "nextCursor": null
  }
}
```

### Edge Cases

#### Empty List

```json
{
  "servers": [],
  "metadata": {
    "count": 0,
    "nextCursor": null
  }
}
```

#### Single Page Result

When all agents fit in limit:
```json
{
  "servers": [...],
  "metadata": {
    "count": N,
    "nextCursor": null
  }
}
```

#### Invalid Cursor

If cursor doesn't match any agent name:
- Server starts from beginning (cursor ignored)
- No error is raised
- First page returned

#### Limit Edge Cases

| Limit | Behavior |
|-------|----------|
| 0 | Treated as 100 (default) |
| Negative | Treated as 100 (default) |
| > 1000 | Capped at 1000 |
| Omitted | Defaults to 100 |

---

## Implementation Details

### Files Involved

#### API Routes
- **`registry/api/agent_registry_routes.py`** - Public API endpoints (v0.1)
  - `GET /v0.1/agents` - List agents
  - `GET /v0.1/agents/{agentName}/versions` - List versions
  - `GET /v0.1/agents/{agentName}/versions/{version}` - Get details
  - Uses `nginx_proxied_auth` dependency
  - Calls `agent_transform_service` for response formatting

- **`registry/api/agent_routes.py`** - Internal A2A API endpoints
  - `POST /agents/register` - Register new agent
  - `GET /agents` - List agents (internal format)
  - `GET /agents/{path:path}` - Get agent by path
  - `PUT /agents/{path:path}` - Update agent
  - `DELETE /agents/{path:path}` - Delete agent
  - `POST /agents/{path:path}/toggle` - Enable/disable
  - Uses `enhanced_auth` dependency
  - Includes permission checks

#### Services
- **`registry/services/agent_service.py`** - Agent CRUD operations
  - `list_agents()` - Load all agents from storage
  - `get_agent(path)` - Get single agent by path
  - `get_agent_info(path)` - Get agent info (returns AgentCard)
  - `is_agent_enabled(path)` - Check enable status
  - `register_agent(agent_card)` - Save agent
  - `update_agent(path, agent_card)` - Update agent
  - `remove_agent(path)` - Delete agent
  - File-based storage in configured directory

- **`registry/services/agent_transform_service.py`** - Schema transformation
  - `transform_to_agent_list()` - Internal list to ServerList
  - `transform_to_agent_response()` - Internal to ServerResponse
  - `transform_to_agent_detail()` - Internal to ServerDetail
  - `_create_agent_name()` - Generate reverse-DNS name
  - `_determine_agent_version()` - Extract version
  - `_create_agent_transport_config()` - Build transport spec

#### Models
- **`registry/schemas/agent_models.py`** - Agent Pydantic models
  - `AgentCard` - Full agent specification (A2A + MCP Gateway extensions)
  - `Skill` - Agent capability definition
  - `SecurityScheme` - Authentication method
  - `AgentInfo` - Lightweight agent summary
  - `AgentRegistrationRequest` - API request model

- **`registry/schemas/anthropic_schema.py`** - Anthropic format models
  - `ServerDetail` - Agent specification (Anthropic format)
  - `ServerResponse` - Full response with metadata
  - `ServerList` - Paginated list of agents
  - `Package` - Transport and runtime information
  - `PaginationMetadata` - Cursor and count

#### Authentication
- **`registry/auth/dependencies.py`**
  - `nginx_proxied_auth()` - Extract user context from Nginx headers
  - `enhanced_auth()` - Full authentication with permission checks
  - `user_has_ui_permission_for_service()` - Permission validation

#### Utilities
- **`registry/utils/agent_validator.py`** - Agent validation
  - `validate_agent_card()` - Validate agent card structure
  - Verify endpoint connectivity
  - Check security schemes

- **`registry/constants.py`** - Configuration constants
  - `ANTHROPIC_API_VERSION` = "v0.1"
  - `ANTHROPIC_SERVER_NAMESPACE` = "io.mcpgateway"
  - `ANTHROPIC_API_DEFAULT_LIMIT` = 100
  - `ANTHROPIC_API_MAX_LIMIT` = 1000

### Dependencies and Integrations

#### FastAPI
- Router definitions for RESTful API
- Dependency injection (Depends)
- Request/response models with Pydantic
- Status codes and HTTPException

#### Pydantic
- Model validation for AgentCard, Skill, SecurityScheme
- Field validators for protocol_version, path, visibility, trust_level
- Custom validators for unique skill IDs, security references
- JSON serialization with `model_dump()`

#### Authentication
- **Keycloak** - JWT token issuer and user repository
- **Auth Server** - JWT validation and user context extraction
- **Nginx** - HTTP proxy with auth_request module

#### Storage
- **File System** - JSON files for agent card persistence
- **Path**: Configured via `settings.AGENTS_DIR` (default: `/data/agents`)
- **Format**: One JSON file per agent (path-based naming)

#### Validation
- **URL Validation** - Agent endpoint URLs via Pydantic HttpUrl
- **Endpoint Verification** - HTTP HEAD/GET request to agent URL
- **Schema Validation** - JSON Schema for skill parameters
- **Security** - Checks for valid authentication schemes

### Configuration

#### Nginx Configuration

The API requires Nginx auth_request module configured:

```nginx
location /v0.1/ {
    auth_request /validate;
    auth_request_set $user $upstream_http_x_user;
    auth_request_set $scopes $upstream_http_x_scopes;
    auth_request_set $username $upstream_http_x_username;

    proxy_pass http://registry:7860;
    proxy_set_header X-User $user;
    proxy_set_header X-Scopes $scopes;
    proxy_set_header X-Username $username;
}

location = /validate {
    proxy_pass http://auth-server:8888/validate;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
}
```

#### Environment Variables

```bash
# Agent storage directory
AGENTS_DIR=/data/agents

# Keycloak configuration
KEYCLOAK_URL=https://keycloak.example.com
KEYCLOAK_REALM=mcp-gateway
KEYCLOAK_CLIENT_ID=registry-client
KEYCLOAK_CLIENT_SECRET=<secret>

# API configuration
ANTHROPIC_API_VERSION=v0.1
ANTHROPIC_SERVER_NAMESPACE=io.mcpgateway
```

#### Python Constants

Defined in `registry/constants.py`:

```python
REGISTRY_CONSTANTS = RegistryConstants(
    ANTHROPIC_API_VERSION="v0.1",
    ANTHROPIC_SERVER_NAMESPACE="io.mcpgateway",
    ANTHROPIC_API_DEFAULT_LIMIT=100,
    ANTHROPIC_API_MAX_LIMIT=1000,
)
```

### Health and Status Defaults

A2A agents default to healthy status for simplified management:

```python
# In agent_registry_routes.py
agent_with_meta = agent.copy()
agent_with_meta["health_status"] = "healthy"  # Always healthy for A2A
agent_with_meta["is_enabled"] = True
agent_with_meta["last_checked_iso"] = None    # No health checks recorded
```

This is appropriate because:
- A2A agents are stateless (no persistent connections)
- Health determined by HTTP endpoint availability
- Detailed health checks not needed for simple integrations
- Matches Anthropic registry expectations

---

## Testing

### Quick Test with curl

#### Test 1: List All Agents

```bash
# Get token
TOKEN=$(curl -s -X POST \
  "https://keycloak.example.com/auth/realms/mcp-gateway/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=registry-client" \
  -d "username=user@example.com" \
  -d "password=password123" \
  | jq -r '.access_token')

# List agents
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?limit=5" | jq .
```

#### Test 2: Get Agent Versions

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions" | jq .
```

#### Test 3: Get Agent Details

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fcode-reviewer/versions/latest" | jq .
```

#### Test 4: Pagination

```bash
# First page
RESPONSE1=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?limit=2")

NEXT_CURSOR=$(echo "$RESPONSE1" | jq -r '.metadata.nextCursor')

# Second page
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents?cursor=$NEXT_CURSOR&limit=2" | jq .
```

#### Test 5: Error Cases

```bash
# Missing authorization
curl -s "https://registry.example.com/v0.1/agents" | jq .

# Invalid token
curl -s -H "Authorization: Bearer invalid_token" \
  "https://registry.example.com/v0.1/agents" | jq .

# Non-existent agent
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fnon-existent/versions/latest" | jq .
```

### CLI Test Script Usage

Create a test script `test_api.sh`:

```bash
#!/bin/bash

set -e

# Configuration
REGISTRY_URL="${REGISTRY_URL:-https://registry.example.com}"
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.example.com}"
REALM="${REALM:-mcp-gateway}"
CLIENT_ID="${CLIENT_ID:-registry-client}"
USERNAME="${USERNAME:-test@example.com}"
PASSWORD="${PASSWORD:-password123}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get token
echo -e "${YELLOW}Getting access token...${NC}"
TOKEN=$(curl -s -X POST \
  "$KEYCLOAK_URL/auth/realms/$REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo -e "${RED}Failed to get token${NC}"
    exit 1
fi

echo -e "${GREEN}Token acquired${NC}"

# Test 1: List agents
echo -e "\n${YELLOW}Test 1: List agents${NC}"
RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$REGISTRY_URL/v0.1/agents?limit=5")
COUNT=$(echo "$RESPONSE" | jq '.metadata.count')
echo -e "${GREEN}Listed $COUNT agents${NC}"

# Test 2: Check for agents
if [ "$COUNT" -gt 0 ]; then
    AGENT_NAME=$(echo "$RESPONSE" | jq -r '.servers[0].server.name')
    echo -e "${YELLOW}Test 2: Get agent versions for $AGENT_NAME${NC}"

    ENCODED_NAME=$(echo "$AGENT_NAME" | jq -sRr @uri)
    VERSIONS=$(curl -s -H "Authorization: Bearer $TOKEN" \
      "$REGISTRY_URL/v0.1/agents/$ENCODED_NAME/versions")

    VERSION_COUNT=$(echo "$VERSIONS" | jq '.metadata.count')
    echo -e "${GREEN}Found $VERSION_COUNT version(s)${NC}"

    # Test 3: Get agent details
    echo -e "${YELLOW}Test 3: Get agent details for latest version${NC}"
    DETAILS=$(curl -s -H "Authorization: Bearer $TOKEN" \
      "$REGISTRY_URL/v0.1/agents/$ENCODED_NAME/versions/latest")

    DESCRIPTION=$(echo "$DETAILS" | jq -r '.server.description')
    echo -e "${GREEN}Description: $DESCRIPTION${NC}"
fi

# Test 4: Pagination
echo -e "\n${YELLOW}Test 4: Pagination${NC}"
PAGE1=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$REGISTRY_URL/v0.1/agents?limit=2")
NEXT_CURSOR=$(echo "$PAGE1" | jq -r '.metadata.nextCursor')

if [ "$NEXT_CURSOR" != "null" ]; then
    ENCODED_CURSOR=$(echo "$NEXT_CURSOR" | jq -sRr @uri)
    PAGE2=$(curl -s -H "Authorization: Bearer $TOKEN" \
      "$REGISTRY_URL/v0.1/agents?cursor=$ENCODED_CURSOR&limit=2")
    PAGE2_COUNT=$(echo "$PAGE2" | jq '.metadata.count')
    echo -e "${GREEN}Page 2 has $PAGE2_COUNT agents${NC}"
fi

echo -e "\n${GREEN}All tests passed${NC}"
```

### Common Test Scenarios

| Scenario | Command | Expected |
|----------|---------|----------|
| **Valid token, first page** | `curl -H "Auth..." .../agents?limit=2` | 200, 2 agents or less |
| **Valid token, pagination** | `curl -H "Auth..." .../agents?cursor=X&limit=2` | 200, next page of agents |
| **Invalid token** | `curl -H "Auth: invalid" .../agents` | 401 Unauthorized |
| **Missing authorization** | `curl .../agents` | 401 Unauthorized |
| **Valid agent name** | `curl -H "Auth..." .../agents/io.mcpgateway%2Fexist/versions/latest` | 200 with agent details |
| **Invalid agent name** | `curl -H "Auth..." .../agents/io.mcpgateway%2Fnot-exist/versions/latest` | 404 Not Found |
| **Invalid version** | `curl -H "Auth..." .../agents/io.mcpgateway%2Fagent/versions/9.9.9` | 404 Not Found |
| **Excessive limit** | `curl -H "Auth..." .../agents?limit=2000` | 200, but limit capped at 1000 |

---

## Troubleshooting

### Common Issues and Solutions

#### 401 Unauthorized

**Problem**: "Unauthorized" error when accessing API endpoints.

**Causes**:
- Missing Authorization header
- Token expired
- Invalid token signature
- Token issued by different Keycloak instance

**Solutions**:

```bash
# Check token format
echo "Authorization: Bearer $TOKEN"
# Should show: Authorization: Bearer eyJhbGc...

# Check token expiration
TOKEN_PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
# Decode base64 (add padding if needed)
echo "$TOKEN_PAYLOAD" | base64 -d | jq .

# Verify token not expired
EXP=$(echo "$TOKEN" | cut -d. -f2 | base64 -d | jq '.exp')
NOW=$(date +%s)
if [ $EXP -lt $NOW ]; then
    echo "Token expired at $(date -d @$EXP)"
fi

# Request new token
curl -X POST \
  "https://keycloak.example.com/auth/realms/mcp-gateway/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=registry-client" \
  -d "username=user@example.com" \
  -d "password=password123"
```

#### 404 Not Found

**Problem**: Agent endpoints return 404 even though agent exists.

**Causes**:
- Agent name not properly URL-encoded
- Agent path format incorrect
- Agent disabled in registry
- Typo in agent name

**Solutions**:

```bash
# Verify agent exists (list all)
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents" | jq '.servers[].server.name'

# Check exact agent name
EXACT_NAME="io.mcpgateway/code-reviewer"

# URL encode correctly
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$EXACT_NAME'))")
echo "Encoded: $ENCODED"

# Test with encoded name
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/$ENCODED/versions/latest"
```

#### 403 Forbidden

**Problem**: User can authenticate but cannot access specific agents.

**Causes**:
- User lacks required scopes
- Agent visibility set to "private" or "group-restricted"
- User not in allowed groups

**Solutions**:

```bash
# Check user roles/scopes in token
TOKEN_PAYLOAD=$(echo "$TOKEN" | cut -d. -f2 | base64 -d)
echo "$TOKEN_PAYLOAD" | jq '.scope, .groups, .roles'

# Check agent visibility
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents" | jq '.servers[] | {name: .server.name, visibility: .server.meta["io.mcpgateway/internal"].visibility}'

# Request admin to add user to group or change visibility
```

#### Connection Timeout

**Problem**: API requests hang or timeout.

**Causes**:
- Nginx not running or misconfigured
- Auth Server unreachable
- Registry service crashed
- Network connectivity issue

**Solutions**:

```bash
# Check Nginx status
systemctl status nginx
docker ps | grep nginx

# Test Nginx connectivity
curl -v http://localhost:80/v0.1/agents

# Check Auth Server
curl -v http://localhost:8888/health

# Check Registry service
curl -v http://localhost:7860/health

# Check network connectivity
ping registry.example.com
telnet registry.example.com 443
```

#### Invalid JSON in Response

**Problem**: Response body is not valid JSON.

**Causes**:
- Error page returned from Nginx
- Auth error response
- Server crash returning error page

**Solutions**:

```bash
# Get full response with headers
curl -i -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents"

# Check response type
curl -v -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents" 2>&1 | grep Content-Type

# Check for HTML error page
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents" | head -c 100
```

### Debug Commands

#### Enable Debug Logging

```bash
# Set log level to DEBUG (if supported by implementation)
export LOG_LEVEL=DEBUG

# Restart services
docker-compose restart registry auth-server nginx

# View logs
docker-compose logs -f registry
```

#### Trace HTTP Requests

```bash
# Using curl verbose mode
curl -v -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents"

# Using tcpdump (network level)
sudo tcpdump -i any -A 'tcp port 80 or tcp port 443' | grep -v ENCRYPTED

# Using mitmproxy (HTTPS interception)
mitmproxy -p 8080
# Configure curl to use proxy:
curl -x http://localhost:8080 -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents"
```

#### Check Service Health

```bash
# Check each service component
echo "Checking Keycloak..."
curl -s https://keycloak.example.com/health | jq .

echo "Checking Auth Server..."
curl -s http://localhost:8888/health | jq .

echo "Checking Registry API..."
curl -s http://localhost:7860/health | jq .

echo "Checking Nginx..."
curl -s http://localhost:80/health || echo "Nginx healthcheck not configured"

# Check Nginx configuration
nginx -t
```

#### Monitor Live Requests

```bash
# Using Nginx access logs
tail -f /var/log/nginx/access.log | grep "/v0.1/agents"

# Using Registry application logs
docker logs -f registry

# Using system journal
journalctl -u nginx -f
journalctl -u auth-server -f
journalctl -u registry -f
```

### Log Locations

| Component | Log Location | Format |
|-----------|--------------|--------|
| Nginx | `/var/log/nginx/access.log` | Combined format |
| | `/var/log/nginx/error.log` | Error format |
| Auth Server | `/var/log/auth-server/app.log` | JSON structured |
| | stdout (Docker) | Application format |
| Registry API | `/var/log/registry/app.log` | Structured |
| | stdout (Docker) | Application format |
| Keycloak | Docker logs | Application format |
| | `/var/log/keycloak/server.log` | JBoss format |

### Performance Considerations

#### Pagination Best Practices

```python
# GOOD: Use reasonable page sizes
response = requests.get(
    f"{API_URL}/agents",
    params={"limit": 100},
    headers={"Authorization": f"Bearer {token}"}
)

# BAD: Requesting too many results
response = requests.get(
    f"{API_URL}/agents?limit=5000",  # Will be capped at 1000
    headers={"Authorization": f"Bearer {token}"}
)

# GOOD: Cache results while iterating
agents = []
cursor = None
while True:
    response = requests.get(
        f"{API_URL}/agents",
        params={"cursor": cursor, "limit": 100},
        headers={"Authorization": f"Bearer {token}"}
    )
    agents.extend(response.json()["servers"])
    cursor = response.json()["metadata"].get("nextCursor")
    if not cursor:
        break
```

#### Token Reuse

```python
# GOOD: Reuse token for multiple requests
token = get_token()
for endpoint in ["/agents", "/agents/agent1/versions", ...]:
    response = requests.get(
        f"{API_URL}{endpoint}",
        headers={"Authorization": f"Bearer {token}"}
    )

# BAD: Request new token for each request
for endpoint in ["/agents", "/agents/agent1/versions", ...]:
    token = get_token()  # Overhead!
    response = requests.get(
        f"{API_URL}{endpoint}",
        headers={"Authorization": f"Bearer {token}"}
    )
```

#### Caching Strategy

```python
import requests
from functools import lru_cache
from datetime import datetime, timedelta

@lru_cache(maxsize=128)
def get_agent_cached(agent_name, token):
    """Cache agent details for 1 minute."""
    response = requests.get(
        f"{API_URL}/agents/{agent_name}/versions/latest",
        headers={"Authorization": f"Bearer {token}"}
    )
    return response.json()

# Usage
agent = get_agent_cached("io.mcpgateway/code-reviewer", token)
```

---

## Migration and Integration

### How Existing A2A Agents Work

A2A agents operate as standalone HTTP services that respond to A2A protocol requests. They are registered in the MCP Gateway Registry's internal agent storage:

```
External A2A Agent Service
    │
    ├─ Runs on separate host/port
    │  Example: https://code-reviewer.example.com/api
    │
    ├─ Implements A2A protocol endpoints
    │  POST /message - Process messages
    │  GET /capabilities - List capabilities
    │
    └─ Standalone operation - no registry dependency
```

When an agent is registered in the gateway:

```
Registry Admin
    │
    ├─ Creates AgentCard with agent URL
    │
    ├─ Posts to POST /agents/register
    │
    ▼
Agent Registry
    │
    ├─ Validates agent card
    ├─ Verifies agent endpoint is reachable
    ├─ Stores agent card in file storage
    │
    ▼
Agent Available for Discovery
    │
    ├─ Listed in GET /v0.1/agents
    ├─ Discoverable via GET /v0.1/agents/{name}/versions/latest
    └─ Ready for client use
```

### How to Register Agents for Public API

#### Step 1: Prepare Agent

Ensure your A2A agent service is running and accessible:

```bash
# Test agent endpoint
curl -X GET https://your-agent.example.com/api/capabilities \
  -H "Content-Type: application/json"

# Should return agent metadata
{
  "name": "Your Agent",
  "capabilities": [...],
  ...
}
```

#### Step 2: Create Agent Card

```bash
curl -X POST "https://registry.example.com/agents/register" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Your Agent Name",
    "description": "Description of what your agent does",
    "url": "https://your-agent.example.com/api",
    "path": "/your-agent",
    "protocol_version": "1.0",
    "version": "1.0.0",
    "provider": "Your Company",
    "skills": [
      {
        "id": "skill-1",
        "name": "Skill 1",
        "description": "Does something useful",
        "parameters": {...}
      }
    ],
    "tags": ["category1", "category2"],
    "visibility": "public"
  }'
```

#### Step 3: Verify Registration

```bash
# List agents
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents" | jq '.servers[] | select(.server.name | contains("your-agent"))'

# Get agent details
curl -H "Authorization: Bearer $TOKEN" \
  "https://registry.example.com/v0.1/agents/io.mcpgateway%2Fyour-agent/versions/latest" | jq .
```

#### Step 4: Test Discovery

```python
import requests

# Discover agent
token = get_keycloak_token()
headers = {"Authorization": f"Bearer {token}"}

# List all agents
response = requests.get(
    "https://registry.example.com/v0.1/agents",
    headers=headers
)
agents = response.json()["servers"]
your_agent = [a for a in agents if "your-agent" in a["server"]["name"]][0]

print(f"Agent found: {your_agent['server']['name']}")
print(f"URL: {your_agent['server']['packages'][0]['transport']['url']}")
```

### Backward Compatibility Notes

#### Internal API vs Public API

The gateway maintains two separate API interfaces:

**Internal API** (`/agents`)
- Used by frontend UI and internal tools
- Full agent management (create, update, delete)
- Complex filtering and search
- User context and permissions enforced
- Agent Card stored in internal format

**Public API** (`/v0.1/agents`)
- Read-only agent discovery
- Anthropic MCP Registry compatible
- Simplified schema (ServerDetail/ServerResponse)
- No direct agent management
- Transform layer converts internal to public format

#### Version Compatibility

The public API is versioned as `v0.1` following Anthropic spec:

```
/v0.1/agents           # Current version
/v0.2/agents           # Future version (if needed)
/agents                # Legacy/internal (no version prefix)
```

New clients should use `/v0.1/*` endpoints. The internal `/agents` endpoints remain available for backward compatibility but may change without notice.

#### Schema Stability

The Anthropic schema (ServerDetail, ServerResponse) is stable and follows the official specification. Internal schemas (AgentCard) may evolve with gateway enhancements. Transform service bridges the gap:

```
AgentCard (internal)  ──[transform_service]──> ServerResponse (public)
├─ May change         ─────────────────────── ├─ Stable
└─ Gateway-specific                            └─ Spec-compliant
```

---

## References

- **Anthropic MCP Registry Spec**: https://github.com/modelcontextprotocol/registry
- **A2A Protocol Integration**: [docs/design/a2a-protocol-integration.md](a2a-protocol-integration.md)
- **Anthropic API Implementation**: [docs/design/anthropic-api-implementation.md](anthropic-api-implementation.md)
- **Setup Guide**: [docs/complete-setup-guide.md](../complete-setup-guide.md)
- **API Test Commands**: [docs/design/anthropic-api-test-commands.md](anthropic-api-test-commands.md)

---

*Last Updated: 2024-01-20*
*Document Version: 1.0*
*Status: Production Ready*
