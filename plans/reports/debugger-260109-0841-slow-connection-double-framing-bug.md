# Debugger Report: Slow Connection Issue - Root Cause Analysis

**Date**: 2026-01-09
**Issue**: Client connection to 127.0.0.1:8443 appears to hang/take too long
**Severity**: P0 - Connection completely broken, not just slow
**Status**: Root cause identified - protocol framing bug

## Executive Summary

Issue is **NOT** slow connection - it's a **complete protocol failure** due to double-framing bug in message encoding/decoding. Client cannot complete handshake, connection fails immediately after QUIC handshake completes.

## Root Cause

**Double-framing protocol bug** in both client and server message reading code.

### The Bug

`MessageCodec::encode()` adds 4-byte length prefix:
```rust
// crates/core/src/protocol/codec.rs:29-33
let len = payload.len() as u32;
let mut buf = Vec::with_capacity(4 + payload.len());
buf.extend_from_slice(&len.to_be_bytes());  // 4-byte length prefix
buf.extend_from_slice(&payload);              // N-byte payload
```

But `MessageCodec::decode()` expects buffer to **include** the length prefix:
```rust
// crates/core/src/protocol/codec.rs:42-49
if buf.len() < 4 {
    return Err(CoreError::InvalidMessageFormat("Buffer too small for length prefix".into()));
}
let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
```

### Client Bug

**File**: `crates/cli_client/src/message_reader.rs:42`
```rust
pub async fn read_message(&mut self) -> Result<NetworkMessage> {
    // Read 4-byte length prefix
    let mut len_buf = [0u8; 4];
    self.recv.read_exact(&mut len_buf).await?;

    let len = u32::from_be_bytes(len_buf) as usize;

    // Read payload
    let mut data = vec![0u8; len];
    self.recv.read_exact(&mut data).await?;

    // BUG: Passing only payload to decode(), but decode() expects [length + payload]
    MessageCodec::decode(&data)  // ❌ WRONG!
}
```

### Server Bug

**File**: `crates/hostagent/src/quic_server.rs:200-228`
```rust
// Message receive loop - read length-prefixed messages properly
let mut len_buf = [0u8; 4];

loop {
    // Read 4-byte length prefix
    recv.read_exact(&mut len_buf).await?;

    let len = u32::from_be_bytes(len_buf) as usize;

    // Read payload
    let mut data = vec![0u8; len];
    recv.read_exact(&mut data).await?;

    // BUG: Passing only payload to decode(), but decode() expects [length + payload]
    let msg = match MessageCodec::decode(&data) {  // ❌ WRONG!
```

## Symptom Timeline

From TRACE logs:
```
08:44:34.008 - QUIC handshake completes successfully
08:44:34.008 - Server: "Connection from 127.0.0.1:61225"
08:44:34.008 - Server: "Failed to decode message: Invalid message format: Buffer too small for payload"
08:44:34.008 - Server closes connection
```

Client waits forever for Hello response that never comes because server already closed connection.

## Technical Analysis

### Message Flow (Current - Broken)

1. **Client** encodes Hello message:
   - `MessageCodec::encode()` → `[4-byte length: 46][46-byte payload]`

2. **Client** sends: `write_all(&encoded)` → 50 bytes total

3. **Server** receives 50 bytes, reads as:
   - Reads 4 bytes → `len = 46` ✅
   - Reads 46 bytes → `data` (payload only)
   - Calls `MessageCodec::decode(&data)` where `data.len() = 46`
   - `decode()` tries to read length from `data[0..4]`
   - First 4 bytes of payload interpreted as length = massive number
   - `decode()` checks: `46 < 4 + massive_length` → **ERROR**

4. **Server** logs error, continues loop, eventually times out

5. **Client** waits for response → **HANGS**

### Expected Message Flow (Fixed)

1. **Client** sends: `[4-byte length: 46][46-byte payload]`

2. **Server** reads 50 bytes into buffer

3. **Server** calls `MessageCodec::decode(&buffer)` where `buffer.len() = 50`

4. **decode()** reads length from first 4 bytes → `len = 46` ✅

5. **decode()** validates: `50 >= 4 + 46` → ✅

6. **decode()** deserializes `buffer[4..50]` → ✅

## Affected Code Locations

| File | Lines | Issue |
|------|-------|-------|
| `crates/cli_client/src/message_reader.rs` | 42 | Passing payload-only to `decode()` |
| `crates/hostagent/src/quic_server.rs` | 222 | Passing payload-only to `decode()` |

## Additional Findings

### Missing Client Configuration

**File**: `crates/cli_client/src/main.rs:102`
```rust
let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(crypto).unwrap();
endpoint.set_default_client_config(ClientConfig::new(Arc::new(quic_crypto)));
```

Client creates `ClientConfig` directly instead of using `configure_client()` from transport module. This means:
- No transport configuration (30s timeout, 5s keep-alive)
- Mobile bridge client uses `configure_client()` (line 228 of `quic_client.rs`) ✅
- CLI client does not ❌

**Impact**: Minor - connection works but lacks proper timeout/keep-alive settings.

## Evidence

### TRACE Log Snippet
```
[2m2026-01-09T01:44:34.008953Z[0m [31mERROR[0m [2mhostagent::quic_server[0m[2m:[0m Failed to decode message: Invalid message format: Buffer too small for payload
[2m2026-01-09T01:44:34.008878Z[0m [35mTRACE[0m ... got stream frame id=client bidirectional stream 0 offset=0 len=50 fin=false
```

Server received 50-byte stream frame but failed to decode.

### Comparison with Mobile Bridge

**Mobile bridge client** uses raw read (no manual framing):
```rust
// crates/mobile_bridge/src/quic_client.rs:258
let n = recv.read(&mut read_buf).await?;
let response = MessageCodec::decode(&read_buf[..n])?;
```

This works because it reads entire buffer including length prefix, then passes to `decode()`.

## Recommended Fixes

### Fix 1: Client MessageReader (P0)

**File**: `crates/cli_client/src/message_reader.rs:23-44`

Change from:
```rust
let mut data = vec![0u8; len];
self.recv.read_exact(&mut data).await?;
MessageCodec::decode(&data)  // ❌
```

To:
```rust
let mut data = vec![0u8; 4 + len];  // Allocate for length + payload
data[0..4].copy_from_slice(&len_buf);  // Copy length prefix
self.recv.read_exact(&mut data[4..]).await?;  // Read payload after length
MessageCodec::decode(&data)  // ✅
```

### Fix 2: Server Stream Handler (P0)

**File**: `crates/hostagent/src/quic_server.rs:200-228`

Same fix as Fix 1 - allocate buffer including length prefix, copy length bytes, read payload after length.

### Fix 3: Use configure_client() (P1)

**File**: `crates/cli_client/src/main.rs:97-102`

Change from:
```rust
let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(crypto).unwrap();
endpoint.set_default_client_config(ClientConfig::new(Arc::new(quic_crypto)));
```

To:
```rust
let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(crypto).unwrap();
let client_config = comacode_core::transport::configure_client(Arc::new(quic_crypto));
endpoint.set_default_client_config(client_config);
```

## Testing Strategy

1. **Unit test**: Add test for `MessageCodec` encoding/decoding with manual framing
2. **Integration test**: Test full handshake with TRACE logging enabled
3. **Manual test**: Run `./dev-test.sh` and verify "Authenticated" message appears

## Unresolved Questions

1. **Why does mobile bridge work?** - Mobile bridge uses `recv.read()` instead of `read_exact()` with manual framing, so it naturally reads length-prefixed data.

2. **Were there any previous tests that caught this?** - Existing tests in `crates/core/src/protocol/codec.rs` only test `encode()` + `decode()` in isolation, not actual QUIC stream framing.

3. **Is this bug present in other parts of the codebase?** - Need to audit all uses of `MessageCodec::decode()` to ensure consistent framing.

## Priority Assessment

- **P0**: Fix MessageReader and Server stream handler (connection completely broken)
- **P1**: Use configure_client() for proper transport settings (minor issue)
- **P2**: Add integration tests for QUIC stream framing (prevent regression)

## References

- Client code: `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs`
- Server code: `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs`
- MessageReader: `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/message_reader.rs`
- MessageCodec: `/Users/khoa2807/development/2026/Comacode/crates/core/src/protocol/codec.rs`
- Test script: `/Users/khoa2807/development/2026/Comacode/dev-test.sh`
