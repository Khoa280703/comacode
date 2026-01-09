#!/bin/bash
# Debug script to capture PTY output and client input
# Run this to reproduce the space key issue

set -e

echo "=== Comacode Space Key Debug Script ==="
echo ""
echo "This script will:"
echo "1. Start hostagent in debug mode"
echo "2. Start cli_client in debug mode"
echo "3. Capture PTY output and client input"
echo ""

# Set RUST_LOG for debug output
export RUST_LOG=debug,comacode_hostagent=trace,comacode_cli_client=trace,portable_pty=trace

echo "Starting hostagent..."
echo "Token will be printed below - copy it for the client"
echo ""

# Start hostagent in background
cargo run -p hostagent 2>&1 | tee /tmp/hostagent-debug.log &
HOSTAGENT_PID=$!

# Wait for hostagent to start
sleep 2

echo ""
echo "Hostagent started with PID: $HOSTAGENT_PID"
echo "Check /tmp/hostagent-debug.log for token"
echo ""
echo "Press Enter to start client..."
read

echo ""
echo "Starting cli_client..."
echo "Type: ping 8.8.8.8"
echo "Press Enter"
echo "Type 'exit' to quit"
echo ""

# Start cli_client with debug
cargo run -p cli_client -- \
  --connect 127.0.0.1:8443 \
  --insecure \
  --token "$(grep 'Token:' /tmp/hostagent-debug.log | awk '{print $2}')" \
  2>&1 | tee /tmp/client-debug.log

echo ""
echo "Debug logs saved to:"
echo "  - /tmp/hostagent-debug.log"
echo "  - /tmp/client-debug.log"
echo ""
echo "Check for:"
echo "  - 'PTY read' messages in hostagent log"
echo "  - 'Client received' messages in client log"
echo "  - Hex dump of space character (0x20)"
echo ""

# Kill hostagent
kill $HOSTAGENT_PID 2>/dev/null || true

echo "=== Debug Complete ==="
