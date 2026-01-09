#!/bin/bash
# Quick test script: Start server + auto-connect client

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Comacode Dev Test ===${NC}"

# Build if needed
if [ ! -f "./target/release/hostagent" ] || [ ! -f "./target/release/cli_client" ]; then
    echo "Building..."
    cargo build --release -p hostagent -p cli_client
fi

# Start hostagent in background, capture output to temp file
TMPFILE=$(mktemp)
echo -e "${GREEN}Starting hostagent...${NC}"
./target/release/hostagent > "$TMPFILE" 2>&1 &
HOSTAGENT_PID=$!

# Wait for startup and extract token
sleep 2
TOKEN=$(grep -oE 'Auth token: ([a-f0-9]{64})' "$TMPFILE" | awk '{print $3}' | head -1)

rm -f "$TMPFILE"

if [ -z "$TOKEN" ] || [ ${#TOKEN} -ne 64 ]; then
    echo -e "${YELLOW}Could not auto-detect token${NC}"
    echo ""
    echo "Run in 2 terminals:"
    echo "  Terminal 1: ./target/release/hostagent"
    echo "  Terminal 2: ./target/release/cli_client --connect 127.0.0.1:8443 --token <TOKEN> --insecure"
else
    echo -e "${GREEN}Token: ${TOKEN:0:16}...${NC}"
    echo ""
    echo -e "${GREEN}Connecting client...${NC}"
    echo -e "${YELLOW}Type /exit or Ctrl+D to disconnect${NC}"
    echo ""
    ./target/release/cli_client --connect 127.0.0.1:8443 --token "$TOKEN" --insecure
fi

# Cleanup
echo ""
echo -e "${GREEN}Cleaning up...${NC}"
kill $HOSTAGENT_PID 2>/dev/null || true
wait $HOSTAGENT_PID 2>/dev/null || true
echo "Done!"
