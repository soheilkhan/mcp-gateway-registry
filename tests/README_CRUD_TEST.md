# CRUD Test Script for A2A Agents

A simple, easy-to-run script that demonstrates all CRUD operations on an A2A agent.

## Quick Start

### Terminal 1: Start the Application
```bash
python -m uvicorn registry.main:app --reload
```

Wait for: `Uvicorn running on http://127.0.0.1:8000`

### Terminal 2: Run the CRUD Test
```bash
bash tests/crud_test_simple.sh
```

That's it! Watch the colored output as it tests all operations.

## What It Tests

The script performs 8 operations on a single agent:

1. **CREATE** (POST /api/agents/register) - Register new agent
2. **READ** (GET /api/agents/{path}) - Retrieve agent details
3. **UPDATE** (PUT /api/agents/{path}) - Modify agent
4. **LIST** (GET /api/agents) - List all agents
5. **TOGGLE** (POST /api/agents/{path}/toggle) - Disable agent
6. **TOGGLE** (POST /api/agents/{path}/toggle) - Re-enable agent
7. **DELETE** (DELETE /api/agents/{path}) - Remove agent
8. **VERIFY** (GET /api/agents/{path}) - Confirm deletion (404)

## Output Features

Each operation shows:
- ✓ Section header with step number
- ✓ Actual curl command
- ✓ Pretty-printed JSON request/response
- ✓ Success/failure indicator
- ✓ HTTP status code

## Customization

Edit `tests/crud_test_simple.sh`:

```bash
# Line 12: Change host/port
HOST="http://localhost:8000"

# Line 13: Use real auth token if needed
TOKEN="test-token"

# Line 15: Change agent name to test
AGENT_PATH="code-reviewer"

# Lines 18-50: Modify agent details (name, description, skills, etc.)
```

## File Locations

**Script:** `tests/crud_test_simple.sh`
**Backup:** `.scratchpad/crud_test_simple.sh`

## Storage

Agent files are created during the test:

After CREATE:
- `registry/agents/code-reviewer.json` - Agent card
- `registry/agents/agent_state.json` - State tracking

After DELETE:
- Files are removed
- agent_state.json is updated

Verify with:
```bash
cat registry/agents/agent_state.json | jq .
```

## Requirements

- Running application on localhost:8000
- `curl` (standard on most systems)
- `jq` (optional, for pretty JSON - script works without it)

## Troubleshooting

**Connection refused:**
→ Make sure app is running (Terminal 1)

**HTTP 409 Conflict:**
→ Agent already exists, delete first or change AGENT_PATH

**No output:**
→ Check if app is responding: `curl http://localhost:8000/api/health`

**jq: command not found:**
→ Optional, script still works. Install with: `sudo apt-get install jq`

## Example Output

```
╔════════════════════════════════════════════════════════════════╗
║ STEP 1: CREATE - Register an Agent                           ║
╚════════════════════════════════════════════════════════════════╝

▶ Command:
  POST /api/agents/register

◀ Response:
{
  "protocol_version": "1.0",
  "name": "Code Reviewer Agent",
  "path": "/agents/code-reviewer",
  ...
}

✓ Agent created successfully!
```

## Full CRUD Operations Summary

```
1. CREATE    - Registered a new agent
2. READ      - Retrieved the agent details
3. UPDATE    - Modified the agent description
4. LIST      - Listed all agents
5. TOGGLE    - Disabled the agent
6. TOGGLE    - Re-enabled the agent
7. DELETE    - Removed the agent
8. VERIFY    - Confirmed the agent no longer exists

✓ CRUD Test Complete!
```

## Next Steps

1. Run the tests: `bash tests/crud_test_simple.sh`
2. Check the storage: `cat registry/agents/agent_state.json | jq .`
3. Run pytest tests: `uv run pytest tests/unit/agents/test_agent_endpoints.py -v`
4. Read design doc: `docs/design/a2a-protocol-integration.md`

---

Simple CRUD testing for A2A agent registration! 🎉
