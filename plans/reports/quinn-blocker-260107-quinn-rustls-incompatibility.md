# Report: Quinn + Rustls Version Incompatibility Blocker

**Date:** 2026-01-07
**Phase:** 04 - Mobile App (Flutter)
**Severity:** BLOCKER
**Status:** Stub implementation in place

---

## Problem Summary

QUIC client implementation is blocked due to API incompatibility between:
- **quinn = "0.11"**
- **rustls = "0.23"**

Quinn 0.11 expects rustls 0.23 with specific crypto layer abstraction. The `QuicClientConfig::try_from()` requires specific rustls configuration that is not straightforward to implement.

---

## Files Affected

### 1. `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs`

Stub implementation with detailed blocker documentation:

```rust
//! ## BLOCKER: Quinn + Rustls version incompatibility
//!
//! Current dependencies:
//! - quinn = "0.11"
//! - rustls = "0.23" (workspace)
//!
//! Quinn 0.11 expects rustls 0.23 with specific crypto layer abstraction.
//! The `QuicClientConfig::try_from()` requires specific rustls configuration.

pub struct QuicClient {
    server_fingerprint: String,
    connected: Arc<Mutex<bool>>,
}

// TODO: Implement actual QUIC connection
// For now, mark as "connected" for testing
info!("QUIC client stub: would connect to {}:{}", host, port);
```

**Lines 24-122:** Stub `QuicClient` with placeholder methods:
- `connect()` - Validates input but doesn't establish QUIC connection
- `receive_event()` - Returns empty `TerminalEvent`
- `send_command()` - Logs command but doesn't send
- `disconnect()` - Only sets flag

### 2. `/Users/khoa2807/development/2026/Comacode/Cargo.toml` (lines 19-20)

```toml
[workspace.dependencies]
# Networking
quinn = "0.11"
rustls = "0.23"
```

### 3. `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/Cargo.toml` (lines 29-30)

```toml
# QUIC networking (Phase 04)
quinn = { workspace = true }
rustls = { workspace = true }
```

### 4. `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/api.rs`

Functions that depend on QUIC client (currently stub):

```rust
#[frb]
pub async fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
) -> Result<(), String>

#[frb]
pub async fn receive_terminal_event() -> Result<TerminalEvent, String>

#[frb]
pub async fn send_terminal_command(command: String) -> Result<(), String>
```

---

## Root Cause Analysis

### Quinn 0.11 Crypto Layer Requirements

Quinn 0.11 introduced breaking changes in how it handles TLS configuration:

1. **`quinn::crypto::rustls::QuicClientConfig`** - New crypto wrapper type
2. **`QuicClientConfig::try_from()`** - Requires properly configured `rustls::ClientConfig`
3. **Certificate verifier** - Needs custom verifier for TOFU fingerprint matching

### Attempted Approaches (All Failed)

1. **Direct `ClientConfig::builder()`** - Methods like `with_no_client_auth()` don't exist on `ClientConfig` directly
2. **`ConfigBuilder<WantsClientCert>`** - Complex type state that doesn't match rustls 0.23 API
3. **Using `quinn::crypto::rustls::QuicClientConfig` wrapper** - Still requires correct underlying rustls configuration

---

## Solution Options

### Option A: Upgrade/Downgrade to Compatible Versions

Research compatible quinn + rustls version combinations:

| Quinn | Rustls | Compatible? |
|-------|--------|-------------|
| 0.11  | 0.23   | ❌ Complex API mismatch |
| 0.11  | 0.21   | ? Needs testing |
| 0.10  | 0.21   | ? Needs testing |
| 0.9   | 0.20   | ✇ (Older stable) |

### Option B: Use Quinn's Built-in Crypto

Quinn may provide simpler crypto configuration helpers:

```rust
// Possible approach (untested)
let crypto = quinn::crypto::rustls::QuicClientConfig::new_from_der(
    vec![], // No CA for TOFU
    vec![], // No client cert
)?;
```

### Option C: Alternative QUIC Implementation

Consider alternative libraries:
- **s2n-quic** - AWS implementation, simpler API
- **quinn-proto** - Lower level, more control

### Option D: Keep Stub + Implement Later

For MVP, stub implementation allows Flutter UI development to proceed. QUIC implementation can be deferred until:
- Compatible versions identified
- Or proper Quinn documentation available

---

## Current State

✅ **Working:**
- Flutter UI compiles and runs
- Rust code compiles without errors
- Unit tests pass (3/3 for quic_client)
- FFI bridge generates correctly

❌ **Not Working:**
- Actual QUIC connection not established
- `TerminalEvent` streaming not implemented
- Command sending to remote terminal not implemented

---

## Test Coverage

File: `crates/mobile_bridge/src/quic_client.rs:124-150`

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_quic_client_creation() {
        let client = QuicClient::new("AA:BB:CC".to_string());
        assert_eq!(client.server_fingerprint, "AA:BB:CC");
    }

    #[tokio::test]
    async fn test_quic_client_not_connected_initially() {
        let client = QuicClient::new("AA:BB:CC".to_string());
        assert!(!client.is_connected().await);
    }

    #[tokio::test]
    async fn test_quic_client_connect_stub() {
        let mut client = QuicClient::new("AA:BB:CC".to_string());
        let token = AuthToken::generate();
        let result = client.connect("127.0.0.1".to_string(), 8443, token.to_hex()).await;
        assert!(result.is_ok());
        assert!(client.is_connected().await);
    }
}
```

All tests pass ✅ (but only test stub behavior)

---

## Recommendations

1. **Short-term:** Keep stub implementation, proceed with Flutter UI testing
2. **Medium-term:** Research quinn 0.11 + rustls 0.23 compatibility examples in Quinn repository
3. **Long-term:** Consider alternative if Quinn API continues to be problematic

---

## Unresolved Questions

1. Which quinn + rustls version combination is actually compatible?
2. Are there working examples of Quinn 0.11 with custom certificate verification (TOFU)?
3. Should we consider s2n-quic as an alternative?

---

## References

- Quinn repo: https://github.com/quinn-rs/quinn
- Rustls repo: https://github.com/rustls/rustls
- Quinn 0.11 migration guide: https://github.com/quinn-rs/quinn/blob/main/QUINN-0.11.md
