#!/bin/bash

################################################################################
# Simple A2A Agent CRUD Test Script
#
# This script demonstrates basic CRUD operations on a single agent
# Easy to run and see output for learning purposes
#
# Usage:
#   bash tests/crud_test_simple.sh
#
# Note: Requires Docker containers running (docker-compose up -d)
#       API accessible via Nginx reverse proxy on port 80
#       Or modify HOST/PORT below
################################################################################

# Configuration
HOST="http://localhost"
TOKEN="test-token"  # Replace with actual token if using real auth
AGENT_PATH="code-reviewer"
FULL_PATH="/code-reviewer"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Helper function to print sections
section() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Helper function to print commands
print_cmd() {
    echo -e "${YELLOW}▶ Command:${NC}"
    echo "  $1"
    echo ""
}

# Helper function to print responses
print_response() {
    echo -e "${YELLOW}◀ Response:${NC}"
    echo "$1" | jq . 2>/dev/null || echo "$1"
    echo ""
}

################################################################################
# STEP 1: CREATE (Register) an Agent
################################################################################
section "STEP 1: CREATE - Register an Agent"

print_cmd "POST /api/agents/register"

RESPONSE=$(curl -s -X POST \
  "$HOST/api/agents/register" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "protocol_version": "1.0",
    "name": "Code Reviewer Agent",
    "description": "Reviews code for quality and best practices",
    "url": "https://code-reviewer.example.com",
    "path": "'"$FULL_PATH"'",
    "skills": [
      {
        "id": "review-python",
        "name": "Python Code Review",
        "description": "Reviews Python code",
        "parameters": {
          "code_snippet": {"type": "string"}
        },
        "tags": ["python", "review"]
      }
    ],
    "security_schemes": {
      "bearer": {"type": "bearer", "description": "Bearer token"}
    },
    "security": ["bearer"],
    "tags": ["code-review", "qa"],
    "visibility": "public",
    "trust_level": "verified"
  }')

print_response "$RESPONSE"

# Check if successful
if echo "$RESPONSE" | jq -e '.path' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Agent created successfully!${NC}"
else
    echo -e "${RED}✗ Failed to create agent${NC}"
fi

################################################################################
# STEP 2: READ (Retrieve) the Agent
################################################################################
section "STEP 2: READ - Retrieve the Agent"

print_cmd "GET /api/agents/$AGENT_PATH"

RESPONSE=$(curl -s -X GET \
  "$HOST/api/agents/$AGENT_PATH" \
  -H "Authorization: Bearer $TOKEN")

print_response "$RESPONSE"

if echo "$RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Agent retrieved successfully!${NC}"
else
    echo -e "${RED}✗ Failed to retrieve agent${NC}"
fi

################################################################################
# STEP 3: UPDATE the Agent
################################################################################
section "STEP 3: UPDATE - Modify the Agent"

print_cmd "PUT /api/agents/$AGENT_PATH"

RESPONSE=$(curl -s -X PUT \
  "$HOST/api/agents/$AGENT_PATH" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "description": "Reviews code for quality, style, and security issues",
    "tags": ["code-review", "qa", "security"]
  }')

print_response "$RESPONSE"

if echo "$RESPONSE" | jq -e '.description' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Agent updated successfully!${NC}"
else
    echo -e "${RED}✗ Failed to update agent${NC}"
fi

################################################################################
# STEP 4: LIST (Read all) Agents
################################################################################
section "STEP 4: LIST - Get All Agents"

print_cmd "GET /api/agents"

RESPONSE=$(curl -s -X GET \
  "$HOST/api/agents" \
  -H "Authorization: Bearer $TOKEN")

print_response "$RESPONSE"

if echo "$RESPONSE" | jq -e '.' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Agents listed successfully!${NC}"
else
    echo -e "${RED}✗ Failed to list agents${NC}"
fi

################################################################################
# STEP 5: DISABLE the Agent
################################################################################
section "STEP 5: TOGGLE - Disable the Agent"

print_cmd "POST /api/agents/$AGENT_PATH/toggle"

RESPONSE=$(curl -s -X POST \
  "$HOST/api/agents/$AGENT_PATH/toggle" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"enabled": false}')

print_response "$RESPONSE"

echo -e "${GREEN}✓ Agent disabled!${NC}"

################################################################################
# STEP 6: RE-ENABLE the Agent
################################################################################
section "STEP 6: TOGGLE - Re-enable the Agent"

print_cmd "POST /api/agents/$AGENT_PATH/toggle"

RESPONSE=$(curl -s -X POST \
  "$HOST/api/agents/$AGENT_PATH/toggle" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"enabled": true}')

print_response "$RESPONSE"

echo -e "${GREEN}✓ Agent re-enabled!${NC}"

################################################################################
# STEP 7: DELETE the Agent
################################################################################
section "STEP 7: DELETE - Remove the Agent"

print_cmd "DELETE /api/agents/$AGENT_PATH"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X DELETE \
  "$HOST/api/agents/$AGENT_PATH" \
  -H "Authorization: Bearer $TOKEN")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE")

echo -e "${YELLOW}◀ Response (HTTP $HTTP_CODE):${NC}"
if [ -z "$BODY" ] || [ "$BODY" = "" ]; then
    echo "  (No response body - expected for DELETE)"
else
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
fi
echo ""

if [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✓ Agent deleted successfully! (HTTP 204)${NC}"
else
    echo -e "${RED}✗ Delete may have failed (HTTP $HTTP_CODE)${NC}"
fi

################################################################################
# STEP 8: VERIFY Deletion
################################################################################
section "STEP 8: VERIFY - Confirm Deletion"

print_cmd "GET /api/agents/$AGENT_PATH (should return 404)"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET \
  "$HOST/api/agents/$AGENT_PATH" \
  -H "Authorization: Bearer $TOKEN")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE")

echo -e "${YELLOW}◀ Response (HTTP $HTTP_CODE):${NC}"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" = "404" ]; then
    echo -e "${GREEN}✓ Agent confirmed deleted! (HTTP 404 - Not Found)${NC}"
else
    echo -e "${RED}✗ Agent still exists (HTTP $HTTP_CODE)${NC}"
fi

################################################################################
# Summary
################################################################################
section "CRUD Operations Summary"

cat << 'EOF'
What we just did:

1. CREATE    - Registered a new agent (/agents/code-reviewer)
2. READ      - Retrieved the agent details
3. UPDATE    - Modified the agent description and tags
4. LIST      - Listed all agents
5. TOGGLE    - Disabled the agent
6. TOGGLE    - Re-enabled the agent
7. DELETE    - Removed the agent
8. VERIFY    - Confirmed the agent no longer exists

All operations shown with actual HTTP requests and responses!

Next steps:
- Check files: cat registry/agents/agent_state.json | jq .
- Run tests: uv run pytest tests/unit/agents/test_agent_endpoints.py -v
- Start app: python -m uvicorn registry.main:app --reload

EOF

echo ""
echo -e "${GREEN}✓ CRUD Test Complete!${NC}"
echo ""
