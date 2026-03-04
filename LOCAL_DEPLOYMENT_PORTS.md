# Local deployment – ports and adding an MCP server

This deployment uses non-default host ports to avoid conflicts with existing services.

## Access URLs

| Service        | URL                          |
|----------------|------------------------------|
| **Registry UI** | http://localhost:9080        |
| **Registry API** | http://localhost:9080/api     |
| **Registry app** | http://localhost:7860         |
| **Auth server** | http://localhost:18888        |
| **Keycloak**   | http://localhost:8080         |
| **Grafana**    | http://localhost:13001        |

## Add an MCP server to test

### Option 1: Internal API (curl)

From the host, with admin credentials from `.env` (`ADMIN_USER` / `ADMIN_PASSWORD`, e.g. `admin` / `admin123`). Use **port 7860** (registry app) so Basic auth is accepted; port 9080 goes through nginx and requires JWT/session, so it returns 401 for Basic auth.

```bash
curl -u "admin:admin123" -X POST "http://localhost:7860/api/internal/register" \
  -F "name=Current Time" \
  -F "description=Current time by timezone" \
  -F "path=/currenttime" \
  -F "proxy_pass_url=http://currenttime-server:8000"
```

The registry runs in Docker and reaches MCP servers by service name (e.g. `http://currenttime-server:8000`). For a server running on the host, use `http://host.docker.internal:PORT/path` (e.g. `http://host.docker.internal:9292/mcp/http`).

### Option 2: Web UI

1. Open http://localhost:9080 (or http://localhost:7860).
2. Log in (Keycloak must be initialized first; see main [installation guide](docs/installation.md)).
3. Click **Register Server** and set:
   - **Server name**: e.g. Current Time
   - **Path**: e.g. `/currenttime`
   - **Proxy pass URL**: `http://currenttime-server:8000` (same Docker network)

### Why a registered server shows "unknown" health

Health is **unknown** when the registry has not yet run a health check for that server:

1. **Background checks** run only for **enabled** servers, and only every **5 minutes** (configurable: `HEALTH_CHECK_INTERVAL_SECONDS`). So right after registration (or after enabling), status can stay "unknown" until the next cycle.
2. **Internal registration** auto-enables the server but does not run a health check in the same request, so the first status appears after the next background run or after a manual refresh.

**What to do:**

- **Enable the server** if it is disabled (toggle in the UI). Disabled servers are not checked and show "disabled".
- **Trigger a check now**: in the UI, use the **Refresh** button (refresh icon) for that server if you have `health_check_service` permission. That runs an immediate health check and updates the status.
- **Wait**: the next background health check (within the interval) will set healthy/unhealthy.

If the status becomes **unhealthy** (e.g. "connection error"), ensure the **Proxy pass URL** is reachable from the registry (e.g. from inside Docker use `http://host.docker.internal:9191/...` instead of `http://localhost:9191/...`).

### Verify discovery

```bash
curl -s http://localhost:9080/.well-known/mcp-servers | head -50
```

### Using the registry gateway to access a server

Once a server is registered and healthy, clients use the **gateway URL** instead of the server's direct URL. The gateway proxies MCP traffic and enforces auth.

**Gateway URL format:** `http://localhost:9080{path}`  
Example for path `/assistants-mcp-server`: **`http://localhost:9080/assistants-mcp-server`**

**Authentication:** Requests to the gateway are validated (session or JWT). You must send a valid session cookie (after logging in at http://localhost:9080) or an `Authorization: Bearer <token>` header.

**From a browser or MCP Inspector:**
1. Log in at http://localhost:9080 (so the session cookie is set).
2. Use the gateway URL as the MCP server URL: `http://localhost:9080/assistants-mcp-server`.
3. If the client runs on the same origin (same host/port), the session cookie is sent automatically.

**From curl (with session cookie):**
1. Log in via browser at http://localhost:9080, then copy the `mcp_gateway_session` cookie from DevTools (Application → Cookies).
2. Call the gateway with that cookie:

```bash
# Replace YOUR_SESSION_COOKIE with the value of mcp_gateway_session
curl -X POST "http://localhost:9080/assistants-mcp-server" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Cookie: mcp_gateway_session=YOUR_SESSION_COOKIE" \
  -d '{"jsonrpc":"2.0","id":"0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

**From an app (e.g. assistants-service):** Configure the MCP server URL to the gateway URL (`http://localhost:9080/assistants-mcp-server`) and ensure the app sends the same auth (e.g. session cookie or Bearer token) that the registry expects for gateway routes.

## Port mapping (host -> container)

- Registry: 9080->80, 9443->443, 7860->7860
- Auth: 18888->8888
- Grafana: 13001->3000
- currenttime: 18000->8000
- fininfo: 18001->8001
- realserverfaketools: 18002->8002
- mcpgw: 18003->8003

## Start/stop

```bash
# Start (from repo root)
docker compose -f docker-compose.prebuilt.yml up -d

# Stop
docker compose -f docker-compose.prebuilt.yml down
```

`.env` is already configured with `REGISTRY_URL=http://localhost:9080`, `ADMIN_PASSWORD=admin123`, and required Keycloak/MongoDB vars for local runs.

---

## Testing the Assistants MCP Server (per assistants-mcp-server repo)

Use this when the **Assistants MCP Server** is registered (e.g. path `/assistants-mcp-server`) and you want to confirm it works as intended per [assistants-mcp-server](https://gitlab.infr.zglbl.net/zeta-aiml/gen-ai/ai-assistants/mcp-servers/assistants-mcp-server).

### 1. Run the Assistants MCP Server

From the assistants-mcp-server repo:

```bash
cd /path/to/mcp-servers/assistants-mcp-server/docker
docker compose up zh-assistants-mcp-server
```

Server will listen at **http://localhost:9191** with:

- Health: `http://localhost:9191/health`
- MCP streamable HTTP: `http://localhost:9191/mcp/http`
- MCP SSE: `http://localhost:9191/mcp/sse`

### 2. Registration in the registry

When registering in the gateway, **Proxy pass URL** must point at the MCP endpoint, not the server root, so the gateway can proxy MCP traffic correctly:

- **Path**: `/assistants-mcp-server` (or your chosen path)
- **Proxy pass URL**: `http://localhost:9191/mcp/http` (streamable-http)

If the registry runs in Docker and the Assistants server runs on the host, use:

- **Proxy pass URL**: `http://host.docker.internal:9191/mcp/http`

### 3. Verify discovery

Check that the server appears in well-known discovery:

```bash
curl -s http://localhost:9080/.well-known/mcp-servers | jq '.servers[] | select(.name | test("Assistants"; "i"))'
```

### 4. Health checks

- **Direct (server)**  
  ```bash
  curl -s http://localhost:9191/health
  ```  
  Expect JSON with `"status": "healthy"` and `"service": "assistants-mcp-server"`.

- **Registry UI**  
  Open http://localhost:9080 and confirm the Assistants server shows as **healthy** (registry runs its own health checks against the backend).

### 5. Test MCP through the gateway (MCP Inspector)

1. Install/run [MCP Inspector](https://github.com/modelcontextprotocol/inspector) (or the one referenced in the [assistants-mcp-server README](https://gitlab.infr.zglbl.net/zeta-aiml/gen-ai/ai-assistants/mcp-servers/assistants-mcp-server)).
2. Connect to the server **via the gateway**:
   - **URL**: `http://localhost:9080/assistants-mcp-server`  
     (Use the exact path you registered; do not add `/mcp` unless your gateway is configured to expose that.)
3. If the gateway uses auth, provide the token or session as required.
4. In Inspector, confirm that the **tools list** matches what the Assistants MCP Server exposes (e.g. assistants-tools, analytics).
5. Invoke at least one tool and confirm a successful response.

### 6. Run assistants-mcp-server unit tests

From the assistants-mcp-server repo:

```bash
cd /path/to/mcp-servers/assistants-mcp-server/docker
docker compose -f docker-compose-common.yml build zh-assistants-mcp-server-base && \
docker compose -f docker-compose-tests.yml up --build --exit-code-from zh-assistants-mcp-server-unit-tests zh-assistants-mcp-server-unit-tests
```

This validates the server in isolation; success indicates the server behaves as designed. Using the gateway (steps 3–5) confirms end-to-end behavior through the registry.
