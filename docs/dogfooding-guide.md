# Comacode Dogfooding Guide

## Overview

This guide explains how to test Comacode by running both the hostagent (backend) and CLI client on your local macOS machine.

## Prerequisites

- macOS 11+ (Big Sur or later)
- Rust toolchain (for building from source)
- Terminal access

## Quick Start

### 1. Build Binaries

```bash
# Build universal binary (ARM64 + x64)
./scripts/build-macos.sh

# Verify build
./scripts/verify-build.sh
```

### 2. Start Hostagent

```bash
# Start the backend server
./target/hostagent-universal

# Expected output:
# 🔐 Comacode Hostagent v0.1.0
# 📡 QUIC server listening on 127.0.0.1:8443
# 🎫 Auth token: abc123... (64 hex chars)
# ℹ️  Run this command to connect from another terminal:
#    ./target/release/cli_client --connect 127.0.0.1:8443 --token abc123... --insecure
```

**IMPORTANT**: Copy the auth token from the output. You need it to connect.

### 3. Connect CLI Client

Open a new terminal window:

```bash
# Connect to hostagent (replace TOKEN with actual token)
cargo run -p cli_client -- --connect 127.0.0.1:8443 --token TOKEN --insecure

# Or use the pre-built binary (if built):
./target/release/cli_client --connect 127.0.0.1:8443 --token TOKEN --insecure
```

### 4. Expected Behavior

The CLI client will:
1. Connect via QUIC
2. Send handshake with auth token
3. Execute test command: `echo 'Hello from CLI Client'`
4. Display output from remote shell
5. Exit when command completes

## Firewall Warning

**IMPORTANT**: On macOS, the firewall may block hostagent on first run.

When prompted:
- Click "Allow" to let hostagent accept incoming connections
- Or manually allow in System Preferences > Security & Privacy > Firewall

If connection fails:
```bash
# Test if port is listening
netstat -an | grep 8443

# If empty, check:
# 1. Hostagent is running
# 2. Firewall is not blocking
# 3. No other process using port 8443
```

## Testing Features

### Auth Token Validation

1. Try connecting with invalid token:
```bash
cargo run -p cli_client -- --connect 127.0.0.1:8443 --token deadbeef... --insecure
```
Expected: Connection rejected or logged as invalid

### Rate Limiting

1. Start hostagent
2. Run CLI client multiple times rapidly
3. After ~5 attempts, expect connection to be rate-limited

### TOFU (Trust On First Use)

1. Delete cert store before testing:
```bash
rm -rf ~/.comacode/cert.der ~/.comacode/key.der
```
2. Start hostagent - new certificate will be generated
3. Check fingerprint in logs
4. Reconnect - certificate should be trusted

## Troubleshooting

### "Invalid token format"
- Token must be exactly 64 hex characters (no spaces)
- Copy token directly from hostagent output

### "Connection refused"
- Check hostagent is running
- Verify correct port (default: 8443)
- Check firewall settings

### "Connection timeout"
- Firewall may be blocking
- Check IP address is correct (127.0.0.1 for local)
- Verify hostagent is listening: `lsof -i :8443`

### Certificate errors
- Use `--insecure` flag for local testing
- Proper certificate pinning for production: TODO (Phase E06+)

## Network Testing Script

For automated testing, use the network test script:

```bash
./scripts/test-network.sh
```

This will:
1. Start hostagent in background
2. Extract auth token
3. Run CLI client test
4. Verify connection and output
5. Clean up background processes

## Building CLI Client

The CLI client is built as part of the standard build:

```bash
# Development build
cargo build -p cli_client

# Release build
cargo build --release -p cli_client
```

Binary location: `target/release/cli_client` (or `target/debug/cli_client`)

## Next Steps

After successful local testing:
- Test on remote macOS machine via SSH
- Test network latency impact
- Test with various terminal commands
- Verify auth token persistence across restarts
