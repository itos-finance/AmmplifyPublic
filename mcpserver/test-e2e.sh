#!/bin/bash
# E2E test script for Ammplify MCP Server
# Tests read tools against Monad mainnet
# Usage: ./test-e2e.sh

set -e

BASE_URL="${MCP_URL:-http://localhost:3100/mcp}"
POOL="0x659bd0bc4167ba25c62e05656f78043e7ed4a9da"
OWNER="0x2a42bE604948c0cce8a1FCFC781089611E2a1ea0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SESSION_ID=""

# Initialize MCP session
init_session() {
  echo -e "${YELLOW}Initializing MCP session...${NC}"
  RESPONSE=$(curl -s -D - "$BASE_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": { "name": "e2e-test", "version": "1.0.0" }
      }
    }' 2>/dev/null)

  SESSION_ID=$(echo "$RESPONSE" | grep -i "mcp-session-id:" | sed 's/.*: //' | tr -d '\r\n')
  if [ -z "$SESSION_ID" ]; then
    echo -e "${RED}FAIL: Could not initialize session${NC}"
    echo "$RESPONSE"
    exit 1
  fi
  echo -e "${GREEN}Session: $SESSION_ID${NC}"
}

# Call an MCP tool
call_tool() {
  local tool_name="$1"
  local args="$2"
  local id="$3"

  RESPONSE=$(curl -s "$BASE_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: $SESSION_ID" \
    -d "{
      \"jsonrpc\": \"2.0\",
      \"id\": $id,
      \"method\": \"tools/call\",
      \"params\": {
        \"name\": \"$tool_name\",
        \"arguments\": $args
      }
    }" 2>/dev/null)

  echo "$RESPONSE"
}

# Test a tool and check for success
test_tool() {
  local name="$1"
  local args="$2"
  local id="$3"

  echo -n "  Testing $name... "
  RESULT=$(call_tool "$name" "$args" "$id")

  # Check if we got content back (SSE format has "data:" lines)
  if echo "$RESULT" | grep -q '"content"'; then
    echo -e "${GREEN}PASS${NC}"
    PASS=$((PASS + 1))
  elif echo "$RESULT" | grep -q '"error"'; then
    echo -e "${RED}FAIL${NC}"
    echo "    Error: $(echo "$RESULT" | grep -o '"message":"[^"]*"' | head -1)"
    FAIL=$((FAIL + 1))
  else
    echo -e "${YELLOW}UNKNOWN${NC}"
    echo "    Response: $(echo "$RESULT" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================"
echo " Ammplify MCP Server E2E Tests"
echo " Target: $BASE_URL"
echo "======================================"
echo ""

# Step 1: Init
init_session
echo ""

# Step 2: List tools
echo -e "${YELLOW}Step 1: Verify tools are registered${NC}"
TOOLS_RESP=$(curl -s "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }' 2>/dev/null)

TOOL_COUNT=$(echo "$TOOLS_RESP" | grep -o '"name"' | wc -l)
echo "  Registered tools: $TOOL_COUNT"
if [ "$TOOL_COUNT" -ge 15 ]; then
  echo -e "  ${GREEN}PASS${NC} (expected >= 15)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC} (expected >= 15, got $TOOL_COUNT)"
  FAIL=$((FAIL + 1))
fi
echo ""

# Step 3: Read tool tests
echo -e "${YELLOW}Step 2: Read tools (middleware)${NC}"
test_tool "get_pools" "{}" 10
test_tool "get_tvl" "{}" 11
test_tool "get_prices" "{\"pool_address\": \"$POOL\"}" 12
test_tool "get_leaderboard" "{\"time_window\": \"all-time\"}" 13
test_tool "get_positions" "{\"owner\": \"$OWNER\"}" 14
test_tool "get_tick_liquidity" "{\"pool_address\": \"$POOL\", \"lower_tick\": -887220, \"upper_tick\": 887220}" 15
echo ""

echo -e "${YELLOW}Step 3: Read tools (on-chain)${NC}"
test_tool "get_pool_info" "{\"pool_address\": \"$POOL\"}" 20
test_tool "get_token_balance" "{\"token\": \"USDC\", \"owner\": \"$OWNER\"}" 21
test_tool "get_token_balance" "{\"token\": \"WETH\", \"owner\": \"$OWNER\"}" 22
test_tool "get_allowance" "{\"token\": \"USDC\", \"owner\": \"$OWNER\"}" 23
echo ""

# Step 4: Resources
echo -e "${YELLOW}Step 4: Resources${NC}"
echo -n "  Testing protocol-info resource... "
RES_RESP=$(curl -s "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 30,
    "method": "resources/read",
    "params": { "uri": "ammplify://protocol-info" }
  }' 2>/dev/null)

if echo "$RES_RESP" | grep -q "Ammplify"; then
  echo -e "${GREEN}PASS${NC}"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC}"
  FAIL=$((FAIL + 1))
fi
echo ""

# Summary
echo "======================================"
echo -e " Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "======================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
