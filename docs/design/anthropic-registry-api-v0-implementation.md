# Anthropic MCP Registry API v0 Implementation Summary

## Overview

This implementation adds compatibility with the [Anthropic MCP Registry REST API v0 specification](https://raw.githubusercontent.com/modelcontextprotocol/registry/refs/heads/main/docs/reference/api/openapi.yaml), enabling seamless integration with MCP ecosystem tooling and downstream applications.

---

## New Files Created

| File | Purpose | Key Components |
|------|---------|----------------|
| [registry/schemas/__init__.py](../../registry/schemas/__init__.py) | Module initialization | Exports all Pydantic models |
| [registry/schemas/anthropic_schema.py](../../registry/schemas/anthropic_schema.py) | Anthropic API schemas | 9 Pydantic models matching official spec |
| [registry/services/transform_service.py](../../registry/services/transform_service.py) | Data transformation | 6 functions to bridge internal/external formats |
| [registry/api/v0_routes.py](../../registry/api/v0_routes.py) | API endpoints | 3 REST endpoints for server discovery |
| [tests/unit/services/test_transform_service.py](../../tests/unit/services/test_transform_service.py) | Transformation tests | 15 test cases |
| [tests/unit/api/test_v0_routes.py](../../tests/unit/api/test_v0_routes.py) | API endpoint tests | 13 test cases |

---

## Modified Files

| File | Changes | Lines Changed |
|------|---------|---------------|
| [registry/main.py](../../registry/main.py) | Added v0 router import and registration | +2 |
| [docker/nginx_rev_proxy_http_only.conf](../../docker/nginx_rev_proxy_http_only.conf) | Added `/v0/` location block with CORS | +47 |
| [docker/nginx_rev_proxy_http_and_https.conf](../../docker/nginx_rev_proxy_http_and_https.conf) | Added `/v0/` location block with CORS | +47 |

---

## Architecture & Data Flow

```
Client Request
    ↓
Nginx (/v0/*)
    ↓
FastAPI (registry:7860)
    ↓
v0_routes.py (Enhanced Auth)
    ↓
server_service (Data Access)
    ↓
transform_service (Format Conversion)
    ↓
Anthropic Schema Response
```

---

## Pydantic Models (`anthropic_schema.py`)

### Core Models

| Model | Purpose | Key Fields |
|-------|---------|-----------|
| `Repository` | Source code repository info | `url`, `source`, `id`, `subfolder` |
| `Package` | Distribution package info | `registryType`, `identifier`, `version`, `transport` |
| `ServerDetail` | Complete server information | `name`, `description`, `version`, `packages` |
| `ServerResponse` | Single server API response | `server: ServerDetail`, `_meta` |
| `ServerList` | Paginated server list | `servers: List[ServerResponse]`, `metadata` |
| `PaginationMetadata` | Pagination state | `nextCursor`, `count` |

### Transport Models

| Model | Type | Key Fields |
|-------|------|-----------|
| `StdioTransport` | Standard I/O | `command`, `args`, `env` |
| `StreamableHttpTransport` | HTTP streaming | `url`, `headers` |
| `SseTransport` | Server-Sent Events | `url` |

### Example Structure

```python
ServerResponse {
    server: ServerDetail {
        name: "io.mcpgateway/example-server",
        version: "1.0.0",
        description: "Example MCP server",
        packages: [
            Package {
                registryType: "mcpb",
                transport: {"type": "streamable-http", "url": "http://..."}
            }
        ],
        _meta: {
            "io.mcpgateway/internal": {
                "path": "/example-server",
                "num_tools": 5,
                "health_status": "healthy"
            }
        }
    },
    _meta: {
        "io.mcpgateway/registry": {
            "last_checked": "2025-10-12T10:00:00Z",
            "health_status": "healthy"
        }
    }
}
```

---

## Transformation Service (`transform_service.py`)

### Private Helper Functions

| Function | Purpose | Input → Output |
|----------|---------|----------------|
| `_create_server_name()` | Convert path to reverse-DNS | `/example-server` → `io.mcpgateway/example-server` |
| `_create_transport_config()` | Build transport object | `proxy_pass_url` → `{type, url}` |
| `_determine_version()` | Get/default version | `server_info` → `"1.0.0"` |
| `_extract_repository_from_description()` | Parse repo info (future) | `description` → `Repository \| None` |

### Public Transformation Functions

| Function | Purpose | Key Logic |
|----------|---------|-----------|
| `transform_to_server_detail()` | Internal → `ServerDetail` | Creates reverse-DNS name, builds packages, adds metadata |
| `transform_to_server_response()` | Internal → `ServerResponse` | Wraps `ServerDetail`, adds registry metadata |
| `transform_to_server_list()` | List → `ServerList` | Sorts by name, implements cursor pagination |

### Key Implementation Details

#### Reverse-DNS Naming Convention

```python
def _create_server_name(server_info: Dict[str, Any]) -> str:
    path = server_info.get("path", "")
    clean_path = path.strip("/")
    return f"io.mcpgateway/{clean_path}"
```

#### Cursor-Based Pagination

```python
def transform_to_server_list(..., cursor: Optional[str], limit: Optional[int]):
    # Sort for consistency
    sorted_servers = sorted(servers_data, key=lambda s: _create_server_name(s))

    # Find cursor position
    start_index = 0
    if cursor:
        for idx, server in enumerate(sorted_servers):
            if _create_server_name(server) == cursor:
                start_index = idx + 1
                break

    # Slice and determine next cursor
    page_servers = sorted_servers[start_index:start_index + limit]
    next_cursor = _create_server_name(sorted_servers[end_index - 1]) if more_results else None
```

---

## API Endpoints (`v0_routes.py`)

### Endpoint Overview

| Endpoint | Method | Purpose | Auth | Pagination |
|----------|--------|---------|------|------------|
| `/v0/servers` | GET | List all accessible servers | Required | ✅ Cursor-based |
| `/v0/servers/{serverName}/versions` | GET | List server versions | Required | ❌ Single version |
| `/v0/servers/{serverName}/versions/{version}` | GET | Get server details | Required | ❌ Single resource |

### 1. List Servers (`GET /v0/servers`)

**Function**: `list_servers()`

**Query Parameters**:
- `cursor` (optional): Pagination cursor
- `limit` (optional): Max results (1-1000, default 100)

**Key Logic**:

```python
async def list_servers(cursor, limit, user_context):
    # 1. Get servers based on admin status
    if user_context["is_admin"]:
        all_servers = server_service.get_all_servers()
    else:
        all_servers = server_service.get_all_servers_with_permissions(
            user_context["accessible_servers"]
        )

    # 2. Filter by UI permissions (list_service)
    accessible_services = user_context.get("accessible_services", [])
    for path, server_info in all_servers.items():
        if "all" not in accessible_services and server_name not in accessible_services:
            continue  # Skip unauthorized

        # 3. Enrich with health data
        health_data = health_service._get_service_health_data(path)
        server_info_with_status["health_status"] = health_data["status"]
        server_info_with_status["last_checked_iso"] = health_data["last_checked_iso"]

    # 4. Transform to Anthropic format
    return transform_to_server_list(filtered_servers, cursor, limit)
```

**Response Example**:

```json
{
  "servers": [
    {
      "server": {
        "name": "io.mcpgateway/example-server",
        "description": "Example MCP server",
        "version": "1.0.0",
        "packages": [...]
      },
      "_meta": {...}
    }
  ],
  "metadata": {
    "nextCursor": "io.mcpgateway/next-server",
    "count": 2
  }
}
```

### 2. List Server Versions (`GET /v0/servers/{serverName}/versions`)

**Function**: `list_server_versions()`

**URL Parameters**:
- `serverName`: URL-encoded reverse-DNS name (e.g., `io.mcpgateway%2Fexample-server`)

**Key Logic**:

```python
async def list_server_versions(serverName, user_context):
    # 1. URL-decode and validate format
    decoded_name = unquote(serverName)
    if not decoded_name.startswith("io.mcpgateway/"):
        raise HTTPException(404, "Server not found")

    # 2. Extract path from reverse-DNS name
    path = "/" + decoded_name.replace("io.mcpgateway/", "")

    # 3. Get server info and check permissions
    server_info = server_service.get_server_info(path)
    if not server_info:
        raise HTTPException(404, "Server not found")

    # 4. Verify user has access
    if not user_context["is_admin"]:
        if server_name not in accessible_services:
            raise HTTPException(404, "Server not found")

    # 5. Return single-item list (we only have one version)
    return transform_to_server_list([server_info_with_status])
```

### 3. Get Server Version (`GET /v0/servers/{serverName}/versions/{version}`)

**Function**: `get_server_version()`

**URL Parameters**:
- `serverName`: URL-encoded reverse-DNS name
- `version`: Version string (`"latest"` or `"1.0.0"`)

**Key Logic**:

```python
async def get_server_version(serverName, version, user_context):
    # 1-4. Same validation as list_server_versions()

    # 5. Validate version (only "latest" or "1.0.0" supported)
    if version not in ["latest", "1.0.0"]:
        raise HTTPException(404, f"Version {version} not found")

    # 6. Enrich with health data
    health_data = health_service._get_service_health_data(path)

    # 7. Transform to ServerResponse
    return transform_to_server_response(server_info_with_status, include_registry_meta=True)
```

**Response Example**:

```json
{
  "server": {
    "name": "io.mcpgateway/example-server",
    "description": "Example MCP server",
    "version": "1.0.0",
    "title": "Example Server",
    "packages": [
      {
        "registryType": "mcpb",
        "identifier": "io.mcpgateway/example-server",
        "version": "1.0.0",
        "transport": {
          "type": "streamable-http",
          "url": "http://example:8000/"
        },
        "runtimeHint": "docker"
      }
    ],
    "_meta": {
      "io.mcpgateway/internal": {
        "path": "/example-server",
        "is_enabled": true,
        "health_status": "healthy",
        "num_tools": 5,
        "tags": ["example"],
        "license": "MIT"
      }
    }
  },
  "_meta": {
    "io.mcpgateway/registry": {
      "last_checked": "2025-10-12T10:00:00Z",
      "health_status": "healthy"
    }
  }
}
```

---

## Authentication & Authorization

### Auth Dependency: `enhanced_auth`

All endpoints use the `enhanced_auth` dependency which returns:

```python
{
    "username": "testuser",
    "groups": ["mcp-registry-admin"],
    "scopes": ["mcp-servers-unrestricted/read"],
    "auth_method": "oauth2",
    "provider": "cognito",
    "accessible_servers": ["server1", "server2"],  # Server-level access
    "accessible_services": ["all"],                # UI-level access
    "ui_permissions": {
        "list_service": ["all"],
        "toggle_service": ["server1"]
    },
    "can_modify_servers": True,
    "is_admin": True
}
```

### Permission Checks

| Check | Location | Logic |
|-------|----------|-------|
| **Admin vs User** | Line 77-84 | Admin → all servers<br>User → filtered by `accessible_servers` |
| **UI Permissions** | Line 87-95 | Check `list_service` permission<br>`"all"` grants universal access |
| **Server-Specific** | Line 173-184 | Verify server in `accessible_services`<br>404 if unauthorized |

---

## Nginx Configuration

### Location Block (`/v0/`)

```nginx
location /v0/ {
    # Proxy to FastAPI registry service
    proxy_pass http://127.0.0.1:7860/v0/;
    proxy_http_version 1.1;

    # Pass request metadata
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Pass cookies for session auth
    proxy_pass_request_headers on;

    # Timeouts
    proxy_connect_timeout 10s;
    proxy_send_timeout 30s;
    proxy_read_timeout 30s;

    # CORS for browser clients
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, Cookie' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
}
```

**Key Points**:
- Authentication handled at FastAPI level via session cookies
- CORS enabled for cross-origin browser requests
- Credentials allowed for cookie-based auth

---

## Test Coverage

### Transformation Service Tests (15 tests)

| Test Category | Tests | Coverage |
|---------------|-------|----------|
| **Name Conversion** | 3 | Simple, nested, trailing slash paths |
| **Transport Config** | 1 | HTTP transport creation |
| **Versioning** | 2 | Default version, metadata version |
| **Detail Transform** | 1 | Full internal → `ServerDetail` |
| **Response Transform** | 2 | With/without registry metadata |
| **List Transform** | 6 | No pagination, limit, cursor, sorting, max limit, empty |

### API Endpoint Tests (13 tests)

| Endpoint | Tests | Scenarios |
|----------|-------|-----------|
| **List Servers** | 4 | Admin sees all, user filtered, pagination, response format |
| **List Versions** | 4 | Success, not found, invalid format, unauthorized |
| **Get Version** | 5 | Latest, specific, unsupported, not found, response format |

### Mock Fixtures

```python
@pytest.fixture
def mock_enhanced_auth_admin():
    """Admin user with full access"""
    return {"is_admin": True, "accessible_services": ["all"], ...}

@pytest.fixture
def mock_enhanced_auth_user():
    """Regular user with limited access"""
    return {"is_admin": False, "accessible_services": ["MCP Gateway Tools"], ...}
```

---

## Key Design Decisions

### 1. Reverse-DNS Naming

**Why**: Anthropic spec uses reverse-DNS format (`org.domain/name`)
**Implementation**: Prefix `io.mcpgateway/` to our path-based names
**Example**: `/example-server` → `io.mcpgateway/example-server`

### 2. Single Version Model

**Why**: We don't currently track server versions
**Implementation**: Always return `"1.0.0"` with `"latest"` alias
**Future**: Can extend with `_meta.version` field

### 3. Cursor-Based Pagination

**Why**: Anthropic spec requires cursor pagination
**Implementation**: Use server name as opaque cursor, sort alphabetically
**Benefit**: Consistent results across requests

### 4. Metadata Preservation

**Why**: Need to preserve internal fields while conforming to spec
**Implementation**: Use `_meta` field for custom data
**Structure**:
- `_meta.io.mcpgateway/internal`: Internal server state
- `_meta.io.mcpgateway/registry`: Health/monitoring data

### 5. Permission Model

**Why**: Must respect existing authentication system
**Implementation**: Reuse `enhanced_auth`, check both server and UI permissions
**Security**: Return 404 (not 403) to avoid revealing server existence

---

## Statistics

| Metric | Count |
|--------|-------|
| **New Lines of Code** | ~745 |
| **New Files** | 6 |
| **Modified Files** | 3 |
| **Pydantic Models** | 9 |
| **API Endpoints** | 3 |
| **Transformation Functions** | 6 |
| **Test Cases** | 28 |
| **Test Files** | 2 |

---

## Related Resources

- **GitHub Issue**: [#175 - Support Anthropic MCP Registry REST API v0](https://github.com/user/repo/issues/175)
- **OpenAPI Spec**: https://raw.githubusercontent.com/modelcontextprotocol/registry/refs/heads/main/docs/reference/api/openapi.yaml
- **User Guide**: https://github.com/modelcontextprotocol/registry/blob/main/docs/guides/consuming/use-rest-api.md

---

This implementation provides full read-only compatibility with the Anthropic MCP Registry API, enabling MCP clients and tools to discover and query servers using the standard API specification.
