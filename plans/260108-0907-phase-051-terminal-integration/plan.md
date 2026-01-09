# Phase 05.1: Terminal Streaming Integration

**Parent Plan**: [Phase 05: Network Protocol](../260106-2127-comacode-mvp/phase-05-network-protocol.md)
**Status**: `pending`
**Priority**: `P0` (Critical - blocks terminal functionality)
**Effort**: `3-5h` (reduced due to tokio util approach)
**Created**: `2026-01-08`

---

## Overview

Phase 05 transport module (`crates/core/src/transport/`) đã hoàn chỉnh nhưng **CHƯA được tích hợp** vào client/server. Phase này sẽ kết nối toàn bộ lại để data flow end-to-end.

### Problem Statement

```
PTY Output ──→ [channel] ──→ [STUB] ──→ QUIC ──→ [STUB] ──→ Flutter
Flutter Input ──→ [STUB] ──→ QUIC ──→ [STUB] ──→ PTY
```

**Current state:**
- ✅ Transport module complete (`pump_pty_to_quic`, `bidirectional_pump`, `Heartbeat`)
- ✅ PTY module complete (`portable-pty`, channel-based output)
- ❌ Client stub implementations (`receive_event()` returns empty)
- ❌ Server stub (PTY output not forwarded)
- ❌ Architectural mismatch: PTY uses channels, transport expects AsyncReadExt

### Goal

```
PTY Output ──→ [adapter] ──→ pump_pty_to_quic ──→ QUIC ──→ pump_quic_to_pty ──→ Flutter
Flutter Input ──→ [stream] ──→ QUIC ──→ bidirectional_pump ──→ PTY
```

---

## Architecture Changes

### PTY Adapter Pattern (Simplified!)

Use tokio utilities - no manual AsyncRead implementation:

```rust
// crates/hostagent/src/session.rs (MODIFY)
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::io::StreamReader;

// Channel -> Stream -> AsyncRead (3 lines!)
let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
let reader = StreamReader::new(stream);
// reader: impl AsyncRead + Unpin → works with pump_pty_to_quic() directly!
```

### Client Stream Management

```rust
// crates/mobile_bridge/src/quic_client.rs
pub struct QuicClient {
    connection: Option<Connection>,
    send_stream: Option<SendStream>,      // NEW: for commands
    recv_stream: Option<RecvStream>,      // NEW: for events
    stream_task: Option<JoinHandle<()>>,  // NEW: background pump
}
```

### Server Bidirectional Pump

```rust
// crates/hostagent/src/quic_server.rs
async fn handle_stream(
    mut send: SendStream,
    mut recv: RecvStream,
    session_mgr: Arc<SessionManager>,
) {
    // 1. Validate Hello
    // 2. Get/create session
    // 3. Spawn bidirectional_pump()
    // 4. Spawn heartbeat
}
```

---

## Implementation Phases

### Phase 1: PTY Adapter (1h)

**File**: `crates/hostagent/src/session.rs` (MODIFY)

**Dependencies**: Add `tokio-stream` and `tokio-util` to `Cargo.toml`

**Tasks**:
1. Add dependency: `tokio-stream = "0.1"` and `tokio-util = { version = "0.7", features = ["io"] }`
2. Add `get_pty_reader()` method to SessionManager
3. Use `ReceiverStream + StreamReader` combo (no manual AsyncRead!)

**Implementation** (using tokio utilities):
```rust
// session.rs - Add method
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::io::StreamReader;

impl SessionManager {
    pub fn get_pty_reader(&self, session_id: u64) -> Option<impl AsyncRead + Unpin> {
        let rx = self.sessions.get(&session_id)?.output_tx.clone();
        // Channel -> Stream -> AsyncRead (easy!)
        let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
        Some(StreamReader::new(stream))
    }
}
```

**Why this works**:
- `ReceiverStream` wraps `mpsc::Receiver` into a `Stream`
- `StreamReader` converts `Stream<Item=Bytes>` to `AsyncRead`
- No Waker/Context complexity - handled by tokio!

**Acceptance**:
- [ ] tokio-stream and tokio-util dependencies added
- [ ] `get_pty_reader()` returns `AsyncRead + Unpin`
- [ ] Works directly with `pump_pty_to_quic()`

---

### Phase 2: Server Integration (1.5h)

**File**: `crates/hostagent/src/quic_server.rs`

**Changes**:
1. Line 52: Use `configure_server()` instead of hard-coded config
2. Line 274: Replace PTY output stub with `pump_pty_to_quic()`
3. Add heartbeat spawn after Hello ACK
4. Add stream cleanup on disconnect

**Code diff**:
```rust
// Line 8: Add import
use comacode_core::transport::{configure_server, bidirectional_pump, Heartbeat};

// Line 52-54: Replace
let cfg = configure_server(cert_vec, key_for_config)?;

// Line 274-277: Replace stub
let pty_reader = session_mgr.get_pty_reader(session_id).await?;
tokio::spawn(pump_pty_to_quic(pty_reader, send));
```

**Acceptance**:
- [ ] Server uses `configure_server()`
- [ ] PTY output forwarded via `pump_pty_to_quic()`
- [ ] Heartbeat spawned per connection
- [ ] 28 tests still passing

---

### Phase 3: Client Integration (1.5h)

**File**: `crates/mobile_bridge/src/quic_client.rs`

**Changes**:
1. Line 219: Use `configure_client()`
2. Add `send_stream`, `recv_stream`, `stream_task` fields
3. Implement proper `receive_event()` using stream
4. Implement proper `send_command()` using stream
5. Implement proper `resize_pty()` using stream

**Code diff**:
```rust
// Line 10: Add import
use comacode_core::transport::{configure_client, pump_quic_to_pty};

// In connect():
let (mut send, mut recv) = connection.open_bi().await?;
self.send_stream = Some(send);
self.recv_stream = Some(recv);

// In receive_event():
let recv = self.recv_stream.as_mut().ok_or("No stream")?;
// Use pump_quic_to_pty pattern to read events
```

**Acceptance**:
- [ ] Client uses `configure_client()`
- [ ] `receive_event()` returns actual TerminalEvent
- [ ] `send_command()` sends via stream
- [ ] `resize_pty()` sends via stream

---

### Phase 4: Testing & Cleanup (1h)

**Tasks**:
1. Add integration test: Client → Server → PTY → Client
2. Test heartbeat timeout detection
3. Test PTY resize via QUIC
4. Verify all 28 tests still pass
5. Update Phase 05 report to "100% Complete"

**Acceptance**:
- [ ] Integration test passes
- [ ] 28/28 hostagent tests pass
- [ ] Manual test: CLI client can send `ls` and see output
- [ ] Phase 05 report updated

---

## Dependencies

### No new dependencies

Using existing:
- `comacode_core::transport` (Phase 05)
- `tokio::sync::mpsc` (PTY output)
- `quinn` (QUIC streams)
- `futures::AsyncReadExt` (PTY adapter)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ~~PTY adapter deadlock~~ | ~~High~~ | ✅ **MITIGATED**: Using tokio utilities |
| Stream cleanup leaks | Medium | Add `AbortHandle` for tasks |
| Heartbeat false positive | Low | Configurable timeout (30s) |
| Channel blocking | Medium | Use bounded channel (capacity 100) |

---

## Open Questions

1. **Stream reuse**: Should client open one stream and reuse, or new per command?
   - **Decision**: One long-lived stream per connection (simpler)

2. **PTY lifecycle**: When to create/destroy PTY session?
   - **Decision**: Create on first Command, destroy on Close

3. **Error propagation**: How to report pump errors to Flutter?
   - **Decision**: Return `TerminalEvent::Error { message }`

---

## Success Criteria

- [ ] CLI client can send `ls` and see output
- [ ] Mobile app can send `ls` and see output (Phase 06)
- [ ] Heartbeat timeout detected after 30s
- [ ] All existing tests pass
- [ ] Zero memory leaks (stream cleanup)

---

## Next Steps

After this phase:
- **Phase 06**: Verify Flutter UI integration
- **Phase 07**: mDNS discovery
- **Phase 08**: Production hardening
