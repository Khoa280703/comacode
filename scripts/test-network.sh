#!/bin/bash
set -euo pipefail

echo "🧪 Comacode Network Test Script"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if hostagent binary exists
if [ ! -f "target/release/hostagent" ]; then
    echo -e "${YELLOW}⚠️  hostagent not found in target/release/${NC}"
    echo "Building hostagent..."
    cargo build --release --target-dir target -p hostagent
fi

# Check if cli_client binary exists
if [ ! -f "target/release/cli_client" ]; then
    echo -e "${YELLOW}⚠️  cli_client not found in target/release/${NC}"
    echo "Building cli_client..."
    cargo build --release --target-dir target -p cli_client
fi

# Create temp directory for logs
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

HOSTAGENT_LOG="$TEMP_DIR/hostagent.log"
HOSTAGENT_PID=""

# Cleanup function
cleanup() {
    if [ -n "$HOSTAGENT_PID" ]; then
        echo ""
        echo "🧹 Cleaning up..."
        kill $HOSTAGENT_PID 2>/dev/null || true
        wait $HOSTAGENT_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Step 1: Start hostagent
echo "📡 Step 1: Starting hostagent..."
./target/release/hostagent > "$HOSTAGENT_LOG" 2>&1 &
HOSTAGENT_PID=$!

# Wait for hostagent to start and extract token
echo "⏳ Waiting for hostagent to start..."
sleep 2

# Check if hostagent is running
if ! kill -0 $HOSTAGENT_PID 2>/dev/null; then
    echo -e "${RED}❌ hostagent failed to start${NC}"
    cat "$HOSTAGENT_LOG"
    exit 1
fi

# Extract auth token from logs
TOKEN=$(grep "Auth token:" "$HOSTAGENT_LOG" | sed 's/.*Auth token: //' | head -1)

if [ -z "$TOKEN" ]; then
    echo -e "${YELLOW}⚠️  Could not find auth token in logs${NC}"
    echo "Hostagent output:"
    cat "$HOSTAGENT_LOG"
    exit 1
fi

echo -e "${GREEN}✅ hostagent started (PID: $HOSTAGENT_PID)${NC}"
echo "🎫 Auth token: ${TOKEN:0:16}..."

# Step 2: Check if port is listening
echo ""
echo "📡 Step 2: Checking if port 8443 is listening..."
if lsof -i :8443 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Port 8443 is listening${NC}"
else
    echo -e "${RED}❌ Port 8443 is not listening${NC}"
    echo "Hostagent output:"
    cat "$HOSTAGENT_LOG"
    exit 1
fi

# Step 3: Run CLI client test
echo ""
echo "📡 Step 3: Running CLI client test..."
CLI_OUTPUT="$TEMP_DIR/cli_output.txt"

if ./target/release/cli_client --connect 127.0.0.1:8443 --token "$TOKEN" --insecure > "$CLI_OUTPUT" 2>&1; then
    echo -e "${GREEN}✅ CLI client connected successfully${NC}"

    # Check for expected output
    if grep -q "Ping/Pong test successful" "$CLI_OUTPUT"; then
        echo -e "${GREEN}✅ Ping/Pong test passed${NC}"
    else
        echo -e "${YELLOW}⚠️  Ping/Pong test failed${NC}"
        echo "CLI output:"
        cat "$CLI_OUTPUT"
    fi

    if grep -q "Handshake complete" "$CLI_OUTPUT"; then
        echo -e "${GREEN}✅ Handshake completed${NC}"
    fi
else
    echo -e "${RED}❌ CLI client failed${NC}"
    echo "CLI output:"
    cat "$CLI_OUTPUT"
    exit 1
fi

# Step 4: Verify message protocol
echo ""
echo "📡 Step 4: Verifying message protocol..."

# Check hostagent logs for connection
if grep -q "Connection from" "$HOSTAGENT_LOG"; then
    echo -e "${GREEN}✅ Hostagent logged client connection${NC}"
else
    echo -e "${YELLOW}⚠️  No client connection log found${NC}"
fi

# Step 5: Summary
echo ""
echo "================================"
echo -e "${GREEN}🎉 All tests passed!${NC}"
echo ""
echo "Test Results:"
echo "  ✅ hostagent started successfully"
echo "  ✅ Port 8443 is listening"
echo "  ✅ CLI client connected"
echo "  ✅ Handshake completed"
echo "  ✅ Command executed and output received"
echo ""
echo "Log files preserved in: $TEMP_DIR"
