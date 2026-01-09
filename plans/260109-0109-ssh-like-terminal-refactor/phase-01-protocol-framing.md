# Phase 01: Protocol Framing Fix

**Priority**: P0 (Critical)
**Effort**: 3h
**Status**: ✅ Done (2026-01-09)

## Overview

Fix critical protocol framing bug in both client and server. Current code uses `read()` instead of `read_exact()`, causing message decode failures.

## Context Links

- [Scout: Client Analysis](../scout/scout-cli-client-report.md) - Lines 110-114, 194-213
- [Scout: Server Analysis](../scout/scout-server-report.md) - Lines 201-214
- [Scout: Transport Analysis](../scout/scout-transport-report.md) - Lines 86-106 (reference)

## Protocol Format

```
[4 bytes length (big endian)] [N bytes payload]
```

**MessageCodec::decode() expects**: Full buffer with length prefix
**Current bug**: `read()` returns partial data, decode fails

## Requirements

1. Client handshake uses `read_exact()` for length prefix
2. Client recv loop accumulates partial reads
3. Server handle_stream uses `read_exact()` pattern from stream.rs
4. All decode calls handle proper framing

## Implementation Steps

### Step 1: Add MessageReader Helper (NEW - Clean Architecture)

**Rationale**: Wrap framing logic in dedicated struct to keep main.rs simple.

**Create**: `crates/cli_client/src/message_reader.rs`
```rust
use anyhow::Result;
use comacode_core::{MessageCodec, NetworkMessage};
use quinn::RecvStream;

/// Helper for reading length-prefixed messages from QUIC stream
pub struct MessageReader {
    recv: RecvStream,
}

impl MessageReader {
    pub fn new(recv: RecvStream) -> Self {
        Self { recv }
    }

    /// Read next complete message from stream
    /// Blocks until full message received
    pub async fn read_message(&mut self) -> Result<NetworkMessage> {
        // Read 4-byte length prefix
        let mut len_buf = [0u8; 4];
        self.recv.read_exact(&mut len_buf).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading length"))?;

        let len = u32::from_be_bytes(len_buf) as usize;

        // Validate size (prevent DoS)
        if len > 16 * 1024 * 1024 {
            return Err(anyhow::anyhow!("Message too large: {} bytes", len));
        }

        // Read payload
        let mut data = vec![0u8; len];
        self.recv.read_exact(&mut data).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading payload"))?;

        // Decode message
        MessageCodec::decode(&data)
            .map_err(|e| anyhow::anyhow!("Decode failed: {}", e))
    }
}
```

### Step 2: Fix Client Handshake (main.rs:110-114)

**Before:**
```rust
let mut buf = vec![0u8; 4096];
let n = match recv.read(&mut buf).await? {
    Some(n) => n,
    None => return Err(anyhow::anyhow!("Closed")),
};
let _ = MessageCodec::decode(&buf[..n])?;
```

**After:**
```rust
mod message_reader;
use message_reader::MessageReader;

// After getting recv from open_bi()
let mut reader = MessageReader::new(recv);
let _ = reader.read_message().await?; // Handshake response
```

### Step 3: Fix Client Recv Loop (main.rs:194-213)

**Before:**
```rust
result = recv.read(&mut recv_buf) => {
    match result {
        Ok(Some(n)) => {
            if let Ok(msg) = MessageCodec::decode(&recv_buf[..n]) {
```

**After:**
```rust
// Use MessageReader in recv loop
let mut reader = MessageReader::new(recv);

loop {
    match reader.read_message().await {
        Ok(msg) => {
            // Handle message directly, no buffer management needed
            match msg {
                NetworkMessage::Event(TerminalEvent::Output { data }) => {
                    let mut stdout = std::io::stdout();
                    let _ = stdout.write_all(&data);
                    let _ = stdout.flush();
                }
                NetworkMessage::Close => break,
                _ => {}
            }
        }
        Err(e) => {
            tracing::error!("Read error: {}", e);
            break;
        }
    }
}
```

### Step 3: Fix Server handle_stream (quic_server.rs:201-214)

**Before:**
```rust
let mut read_buf = vec![0u8; 1024];

loop {
    match recv.read(&mut read_buf).await? {
        Some(n) if n > 0 => {
            let msg = match MessageCodec::decode(&read_buf[..n]) {
```

**After:**
```rust
let mut len_buf = [0u8; 4];

loop {
    // Read length prefix
    recv.read_exact(&mut len_buf).await
        .map_err(|_| anyhow::anyhow!("Stream closed"))?;

    let len = u32::from_be_bytes(len_buf) as usize;

    // Validate size
    if len > 16 * 1024 * 1024 {
        tracing::error!("Message too large: {}", len);
        break;
    }

    // Read payload
    let mut data = vec![0u8; len];
    recv.read_exact(&mut data).await
        .map_err(|_| anyhow::anyhow!("Stream closed while reading payload"))?;

    // Decode message
    let msg = match MessageCodec::decode(&data) {
```

## Related Code Files

### Modify
- `crates/cli_client/src/main.rs` - Lines 110-114, 194-213
- `crates/hostagent/src/quic_server.rs` - Lines 201-214

### Reference
- `crates/core/src/transport/stream.rs` - Lines 86-106 (correct pattern)
- `crates/core/src/protocol/codec.rs` - Protocol format

## Todo List

- [ ] Fix client handshake framing (main.rs:110-114)
- [ ] Fix client recv loop accumulation (main.rs:194-213)
- [ ] Fix server handle_stream framing (quic_server.rs:201-214)
- [ ] Test with actual client-server connection
- [ ] Verify all message types decode correctly

## Success Criteria

1. All messages decode without errors
2. Partial reads handled correctly
3. Connection doesn't drop silently
4. Terminal prompt displays correctly

## Risk Assessment

**Risk**: Buffer management complexity in recv loop
**Mitigation**: Reference stream.rs pattern, test thoroughly

**Risk**: Regression in existing functionality
**Mitigation**: Test each change independently

## Security Considerations

- Message size validation prevents DoS
- Length prefix prevents buffer overflow
- read_exact() prevents partial read attacks
