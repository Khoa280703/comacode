---
title: "Phase 05: macOS Build + Testing"
description: "macOS build configuration, CLI client, manual dogfooding guide, local network testing"
status: pending
priority: P1
effort: 5.5h
phase: 05
created: 2026-01-07
revised: 2026-01-07 (Added CLI client, firewall warning, --target-dir fix)
---

## Objectives

Build stable macOS binary cho hostagent, create CLI client để test backend, document manual dogfooding process, và verify all features work qua local network testing.

## Tasks

### 5.1 macOS Build Configuration (1h)

**File**: `.cargo/config.toml` (optional, for default flags)

```toml
[build]
# Target macOS universal binary (M1 + Intel)
target = ["aarch64-apple-darwin", "x86_64-apple-darwin"]

[target.aarch64-apple-darwin]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]

[target.x86_64-apple-darwin]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]
```

**Build script** (`scripts/build-macos.sh`):
```bash
#!/bin/bash
set -euo pipefail

echo "Building Comacode for macOS..."

# Build for M1 (ARM64) - EXPLICIT target-dir for workspace consistency
cargo build --release --target aarch64-apple-darwin --target-dir target -p hostagent

# Build for Intel (x64)
cargo build --release --target x86_64-apple-darwin --target-dir target -p hostagent

# Create universal binary using lipo
lipo -create \
  -output target/hostagent-universal \
  target/aarch64-apple-darwin/release/hostagent \
  target/x86_64-apple-darwin/release/hostagent

echo "✅ Universal binary created: target/hostagent-universal"

# Verify binary architecture
file target/hostagent-universal
# Expected: Mach-O universal binary with 2 architectures: [x86_64:Mach-O x86_64] [arm64]

# Optional: Strip symbols for smaller size
# strip target/hostagent-universal

# Optional: Create dmg installer
# hdiutil create ...
```

**Key change**: `--target-dir target` flag ensures binary path consistency in workspace monorepo.

### 5.2 Build Verification (30min)

**File**: `scripts/verify-build.sh`

```bash
#!/bin/bash

echo "Verifying macOS build..."

# Check binary architecture
file target/hostagent-universal
# Expected: Mach-O universal binary with 2 architectures

# Check for stripped symbols (release mode)
nm target/hostagent-universal | wc -l
# Should be minimal

# Check binary size
SIZE=$(du -h target/hostagent-universal | cut -f1)
echo "Binary size: $SIZE"
# Target: <10MB

# Run binary (help check)
./target/hostagent-universal --help
# Should display usage

echo "✅ Build verification complete"
```

### 5.3 CLI Client Implementation (2h) - NEW

**Purpose**: Minimal QUIC client để test backend without Flutter app.

**File**: `crates/cli_client/Cargo.toml`

```toml
[package]
name = "cli_client"
version.workspace = true
edition.workspace = true

[[bin]]
name = "cli_client"
path = "src/main.rs"

[dependencies]
comacode-core = { path = "../core" }
anyhow = { workspace = true }
clap = { version = "4.5", features = ["derive"] }
tokio = { workspace = true }
quinn = { workspace = true }
rustls = { workspace = true }
```

**File**: `crates/cli_client/src/main.rs`

```rust
//! Minimal QUIC client để test Comacode backend
//!
//! Features:
//! - Connect to hostagent via QUIC
//! - Send/receive NetworkMessage
//! - Interactive command mode
//! - Test auth + rate limiting + TOFU

use anyhow::Result;
use clap::Parser;
use comacode_core::{AuthToken, NetworkMessage, MessageCodec};
use quinn::{Endpoint, ClientConfig};
use rustls::{pki_types::ServerName, ClientConfig as RustlsClientConfig};
use rustls::crypto::ring::cipher_suite::TLS13_AES_128_GCM_SHA256;
use std::net::SocketAddr;
use std::sync::Arc;
use std::io::{self, Write};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[derive(Parser, Debug)]
struct Args {
    /// Host address to connect to
    #[arg(short, long, default_value = "127.0.0.1:8443")]
    connect: SocketAddr,

    /// Auth token (REQUIRED - copy from hostagent output)
    #[arg(short, long)]
    token: String,  // REQUIRED, not Option

    /// Skip certificate verification (TESTING ONLY)
    #[arg(long, default_value_t = false)]
    insecure: bool,
}

/// Certificate verifier that skips verification (TESTING ONLY)
struct SkipVerification;

impl rustls::client::danger::ServerCertVerifier for SkipVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::crypto::SupportedCipherSuite> {
        vec![TLS13_AES_128_GCM_SHA256.into()]
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeValidated, rustls::Error> {
        Ok(rustls::client::danger::HandshakeValidated::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeValidated, rustls::Error> {
        Ok(rustls::client::danger::HandshakeValidated::assertion())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    println!("🔧 Comacode CLI Client");
    println!("📡 Connecting to {}...", args.connect);

    // Validate token format (must be 64 hex chars)
    let token = AuthToken::from_hex(&args.token)
        .map_err(|_| anyhow::anyhow!("Invalid token format. Expected 64 hex characters from hostagent."))?;

    // Create QUIC endpoint
    let mut endpoint = Endpoint::client("0.0.0.0:0".parse()?)?;

    // Configure TLS (skip verification for testing)
    let crypto = if args.insecure {
        RustlsClientConfig::builder()
            .dangerous()
            .with_certificate_verifier(Arc::new(SkipVerification))
            .build()?
    } else {
        // Proper verification (requires CA cert)
        return Err(anyhow::anyhow!("Proper verification not implemented, use --insecure for testing"));
    };

    let config = ClientConfig::new(Arc::new(crypto));
    endpoint.set_default_client_config(config);

    // Connect to host
    let connection = endpoint
        .connect(args.connect, ServerName::try_from("comacode.local")?)?
        .await?;

    println!("✅ Connected to {}", args.connect);

    // Open bidirectional stream
    let (mut send, mut recv) = connection.open_bi().await?;
    println!("📡 Stream opened");

    // Send Hello with validated token (already validated above)
    let hello = NetworkMessage::hello(Some(token));
    let encoded = MessageCodec::encode(&hello)?;
    send.write_all(&encoded).await?;
    println!("🤝 Handshake sent");

    // Read Hello response
    let mut buf = vec![0u8; 1024];
    let n = recv.read(&mut buf).await?.ok_or_else(|| anyhow::anyhow!("Connection closed"))?;
    let response = NetworkMessage::decode(&buf[..n])?;
    println!("✅ Handshake complete: {:?}", std::mem::discriminant(&response));

    // Send initial command to start session
    let cmd = NetworkMessage::Command(comacode_core::TerminalCommand {
        text: "echo 'Hello from CLI Client'".to_string(),
    });
    send.write_all(&MessageCodec::encode(&cmd)?).await?;
    println!("📝 Command sent");

    // Read output
    let mut stdout = io::stdout().lock();
    loop {
        let n = recv.read(&mut buf).await?;
        if n == 0 {
            println!("📡 Connection closed");
            break;
        }
        if let Ok(msg) = NetworkMessage::decode(&buf[..n]) {
            match msg {
                NetworkMessage::Event(event) => {
                    write!(stdout, "{}", event.text)?;
                    stdout.flush()?;
                }
                NetworkMessage::Close => {
                    println!("📡 Server closed connection");
                    break;
                }
                _ => {}
            }
        }
    }

    Ok(())
}
```

**Update workspace `Cargo.toml`**:
```toml
[workspace.members]
...
    "crates/cli_client",
```

### 5.4 Dogfooding Guide (1h) - REVISED

**File**: `docs/dogfooding-guide.md`

```markdown
# Comacode Dogfooding Guide

## Setup

### 1. Build Hostagent
```bash
cd /path/to/comacode
./scripts/build-macos.sh
./scripts/verify-build.sh
```

### 2. Build CLI Client
```bash
cargo build --release --bin cli_client
```

### 3. ⚠️ macOS Firewall Warning

macOS Firewall có thể chặn incoming connections cho unsigned apps.

**Symptoms**: Hostagent chạy nhưng client không kết nối được

**Solutions**:
1. **Quick fix**: System Settings > Network > Firewall > Off (tạm thời test)
2. **Allow**: Lần đầu chạy, macOS sẽ prompt "Allow incoming connections?" → Chọn "Allow"
3. **Workaround**: Remove extended attributes (testing only)
   ```bash
   xattr -cr target/hostagent-universal
   ```

### 4. Start Hostagent
```bash
./target/hostagent-universal

# Expected output:
# ✅ Starting Comacode Host Agent v0.1.0-mvp
# ✅ QUIC server listening on 0.0.0.0:8443
# ✅ Auth token: deadbeef1234...
# ✅ Certificate fingerprint: A1:B2:C3:D4:...
# ✅ Local IP: 192.168.1.100
# ✅ Scan QR code to connect:
# [QR CODE Unicode]
# ✅ IP: 192.168.1.100
# ✅ Port: 8443
# ✅ Fingerprint: A1:B2:C3:...
```

### 5. Test với CLI Client
```bash
# Terminal 2: Run CLI client
# NOTE: --token is REQUIRED, copy from hostagent output
./target/release/cli_client --connect 192.168.1.100:8443 \
    --token deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890 \
    --insecure

# Expected output:
# 🔧 Comacode CLI Client
# 📡 Connecting to 192.168.1.100:8443...
# ✅ Connected to 192.168.1.100:8443
# 📡 Stream opened
# 🤝 Handshake sent
# ✅ Handshake complete
# 📝 Command sent
# Hello from CLI Client
# 📡 Connection closed
```

### 6. Lưu ý về Token

**IMPORTANT**: `--token` flag là **BẮT BUỘC**

```bash
# SAI: Thiếu token
$ ./target/release/cli_client --insecure
error: the following required arguments were not provided:
  --token <TOKEN>

# SAI: Token format sai
$ ./target/release/cli_client --token invalid --insecure
Error: Invalid token format. Expected 64 hex characters from hostagent.

# ĐÚNG: Copy token từ hostagent output
$ ./target/hostagent-universal
✅ Auth token: deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890

$ ./target/release/cli_client --token deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890 --insecure
✅ Connected
```

## Test Scenarios

### Scenario 1: Basic Connection
1. Start hostagent
2. Run CLI client with --insecure
3. Verify connection succeeds
4. ✅ PASS if "Handshake complete" shown

### Scenario 2: Auth Token Validation
1. Start hostagent (note the token)
2. Run CLI client with correct token: `--token <valid>`
3. Verify connection succeeds
4. Run CLI client with wrong token: `--token aabbccdd...`
5. Verify connection rejected
6. ✅ PASS if valid=success, invalid=rejected

**Note**: CLI client requires --token flag (no default value)

### Scenario 3: Rate Limiting
1. Start hostagent
2. Run CLI client 6 times rapidly
3. Verify 6th attempt fails/blocked
4. ✅ PASS if rate limit works

### Scenario 4: TOFU Verification
1. Start hostagent (note fingerprint)
2. Run CLI client with --insecure
3. Restart hostagent (new cert generated)
4. Run CLI client again
5. Note: CLI with --insecure won't detect fingerprint change
6. For proper TOFU test, need to implement fingerprint check
7. ✅ PARTIAL (TOFU needs Flutter app for full testing)

### Scenario 5: Command Streaming
1. Start hostagent
2. Run CLI client
3. Client sends: `echo test`
4. Verify output received
5. ✅ PASS if bidirectional streaming works

### Scenario 6: Rapid Output
1. Start hostagent
2. Run CLI client
3. Send: `yes | head -100`
4. Monitor for backpressure handling
5. ✅ PASS if no crashes

## Performance Benchmarks

### Latency Test
```bash
# Measure time from command send to output receive
# Expected: <50ms on local WiFi
```

### Throughput Test
```bash
# On hostagent: `cat /dev/urandom | base64 | head -c 10M`
# Measure time to transfer 10MB
# Expected: <5s on local WiFi
```

### Memory Usage
```bash
# Monitor hostagent RSS
# Expected: <50MB idle
```

## Known Issues

### Issue 1: QR Code Scanning
**Status**: Phase E05 uses CLI client, no QR scanning needed
**Future**: Flutter app (E06) will implement QR scanning

### Issue 2: Certificate Verification
**Status**: CLI client uses --insecure flag (skips verification)
**Future**: Implement proper cert verification in CLI

### Issue 3: WiFi to Cellular Switch
**Status**: Not supported in MVP (same network required)
**Future**: Add relay server

### Issue 4: IPv6 Networks
**Status**: Not tested
**Future**: Add dual-stack support
```

### 5.5 Local Network Testing (30min)

**File**: `scripts/test-network.sh`

```bash
#!/bin/bash

set -euo pipefail

echo "🧪 Comacode Network Testing"

# Get local IP
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1)
echo "📡 Local IP: $LOCAL_IP"

# Build binaries
echo "🔨 Building binaries..."
./scripts/build-macos.sh
cargo build --release --bin cli_client

# Start hostagent
echo "🚀 Starting hostagent..."
./target/hostagent-universal &
HOSTAGENT_PID=$!

sleep 2

# Test connection
echo "🧪 Testing connection..."
# Get token from hostagent output (requires manual copy or parsing)
# For automation, we'll use --insecure without token validation test
# NOTE: In real usage, user must copy --token from hostagent output
echo ""
echo "⚠️  NOTE: Copy the --token value from hostagent output above"
echo "⚠️  Then run: ./target/release/cli_client --connect $LOCAL_IP:8443 --token <TOKEN> --insecure"
echo ""
# For automated testing, skip for now (requires token parsing)
# if ./target/release/cli_client --connect "$LOCAL_IP:8443" --insecure; then

# Cleanup
kill $HOSTAGENT_PID 2>/dev/null || true
wait $HOSTAGENT_PID 2>/dev/null || true

echo "🏁 Network testing complete"
```

### 5.6 CI Configuration (30min) - OPTIONAL

**File**: `.github/workflows/build-macos.yml`

```yaml
name: Build macOS

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - run: ./scripts/build-macos.sh
      - run: ./scripts/verify-build.sh
      - uses: actions/upload-artifact@v3
        with:
          name: hostagent-macos
          path: target/hostagent-universal
```

---

## Testing Checklist

**Pre-Flight Checks**:
- [ ] Universal binary builds successfully
- [ ] Binary size <10MB
- [ ] `--help` flag works
- [ ] CLI client builds

**Functional Tests**:
- [ ] CLI client connects to hostagent
- [ ] Handshake completes successfully
- [ ] Auth token validation works
- [ ] Command sending/receiving works
- [ ] Rate limiting works (6 attempts)

**Edge Cases**:
- [ ] Wrong token → rejection
- [ ] Invalid IP → connection fails
- [ ] Hostagent restart → reconnect works

**Performance**:
- [ ] Latency <100ms (local)
- [ ] Memory <50MB idle

---

## Acceptance Criteria

- ✅ Universal macOS binary builds (ARM64 + x64)
- ✅ CLI client can connect and send commands
- ✅ Dogfooding guide documented
- ✅ Firewall workaround documented
- ✅ All test scenarios pass
- ✅ No crashes during testing

---

## Dependencies

- Phase 01-04 (All features must be implemented)
- Quinn QUIC library
- Rustls TLS library

---

## Blocked By

- None (but requires Phase 01-04 complete)

---

## Notes

**Code Signing**: Deferred for MVP
- Without signing, macOS shows "unidentified developer" warning
- Users must right-click → Open to bypass
- Acceptable for internal testing

**Notarization**: Not needed for MVP
- Only required for public distribution
- Skip for now

**Distribution**: For MVP, use:
- Manual download (Google Drive, etc.)
- Or GitHub Releases (free)

**CLI Client Scope**: TEST ONLY
- Not production-ready
- Uses --insecure flag
- For backend verification only

---

## Performance Targets

| Metric | Target | Actual |
|--------|--------|--------|
| Binary Size | <10MB | TBD |
| Cold Start | <500ms | TBD |
| Latency (local) | <100ms | TBD |
| Memory (idle) | <50MB | TBD |

Fill in "Actual" column during dogfooding.
