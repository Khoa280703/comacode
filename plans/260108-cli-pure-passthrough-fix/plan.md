---
title: "Fix CLI Client - Pure Passthrough Protocol"
description: "Fix echo conflict by adding NetworkMessage::Input for raw byte passthrough"
status: pending
priority: P0
effort: 1h 5m
branch: main
tags: [cli, bug-fix, protocol, raw-mode]
created: 2026-01-08
---

# Fix CLI Client - Pure Passthrough Protocol

## Context

**Root Cause** (user feedback):
- Current code uses `NetworkMessage::Command` with String conversion
- `String::from_utf8_lossy()` corrupts control bytes
- Double echo conflict: Local + PTY echo

**The Right Way**:
- Client: NO local echo, pure passthrough
- Server: Write raw bytes to PTY, let PTY handle echo & signals
- Protocol: New `NetworkMessage::Input { data: Vec<u8> }`

---

## Implementation Steps

### Step 1: Add NetworkMessage::Input Variant (5min)

**File**: `crates/core/src/types/message.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum NetworkMessage {
    Hello {
        protocol_version: u8,
        app_version: String,
        auth_token: Option<AuthToken>,
    },
    Command(TerminalCommand),

    /// NEW: Raw input bytes for pure passthrough
    /// Client sends raw keystrokes, server writes directly to PTY
    /// PTY handles echo & signal generation (Ctrl+C = SIGINT)
    Input {
        /// Raw bytes from stdin (including control chars)
        data: Vec<u8>,
    },

    Event(TerminalEvent),
    Resize { rows: u16, cols: u16 },
    Close,
}
```

### Step 2: Client - Pure Passthrough (20min)

**File**: `crates/cli_client/src/main.rs`

```rust
// Replace stdin task - NO local echo, NO String conversion
let mut stdin_task = tokio::task::spawn_blocking(move || {
    let mut stdin = std::io::stdin();
    let mut buf = [0u8; 1024];

    loop {
        match stdin.read(&mut buf) {
            Ok(0) => break, // EOF
            Ok(n) => {
                // Check /exit BEFORE any processing
                let text = String::from_utf8_lossy(&buf[..n]).to_string();
                if text.trim() == "/exit" {
                    break;
                }

                // Send RAW bytes via Input message
                // NO String conversion for actual input!
                let msg = NetworkMessage::Input {
                    data: buf[..n].to_vec(),
                };
                let encoded = match MessageCodec::encode(&msg) {
                    Ok(e) => e,
                    Err(_) => break,
                };
                if stdin_tx.blocking_send(encoded).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
});

// Main loop - receive encoded Input from channel
Some(encoded) = stdin_rx.recv() => {
    // Send pre-encoded message directly
    if send.write_all(&encoded).await.is_err() {
        break;
    }
}

// Output - ONLY write what server sends
NetworkMessage::Event(TerminalEvent::Output { data }) => {
    let _ = stdout_lock.write_all(&data);
    let _ = stdout_lock.flush();
}
```

### Step 3: Server - Handle Input Message (15min)

**File**: `crates/hostagent/src/quic_server.rs`

```rust
NetworkMessage::Input { data } => {
    // Write raw bytes directly to PTY
    // PTY handles:
    // - Echo back to client
    // - Signal generation (0x03 -> SIGINT)
    // - All other control sequences
    if let Some(id) = session_id {
        if let Err(e) = session_mgr.write_to_session(id, &data).await {
            tracing::error!("Failed to write input to PTY: {}", e);
        }
    } else {
        tracing::error!("No session for Input message");
    }
}

// Keep Command for backward compatibility (if any)
NetworkMessage::Command(cmd) => {
    // Deprecated: Use Input instead
    if let Some(id) = session_id {
        if let Err(e) = session_mgr.write_to_session(id, cmd.text.as_bytes()).await {
            tracing::error!("Failed to write command to PTY: {}", e);
        }
    }
}
```

### Step 4: Fix mobile_bridge Breaking Change (15min)

**Breaking Change**: Adding `Input` variant breaks mobile_bridge compile.

**File**: `crates/mobile_bridge/src/quic_client.rs` (or wherever NetworkMessage is matched)

```rust
// Add handler for Input variant
match msg {
    NetworkMessage::Hello { .. } => { /* existing */ }
    NetworkMessage::Command(cmd) => { /* existing */ }
    NetworkMessage::Event(event) => { /* existing */ }

    // NEW: Handle raw input (same as cli_client)
    NetworkMessage::Input { data } => {
        // Send raw bytes to QUIC stream
        if let Some(send) = &self.send {
            let _ = send.write_all(&MessageCodec::encode(&msg)?).await;
        }
    }

    NetworkMessage::Resize { .. } => { /* existing */ }
    NetworkMessage::Close => { /* existing */ }
}
```

**Verify**: Compile mobile_bridge after adding Input variant.

```bash
cargo build --release -p mobile_bridge
```

### Step 5: Verify All Crates Build (5min)

```bash
# Build entire workspace
cargo build --release --workspace

# Should succeed with 0 errors
```

---

## Testing Checklist

- [ ] Space key works correctly (no character loss)
- [ ] Backspace works correctly
- [ ] Ctrl+C stops `ping 8.8.8.8`
- [ ] `vim` can edit, save, quit
- [ ] `htop` displays correctly
- [ ] `/exit` cleanly disconnects
- [ ] No double echo
- [ ] No display corruption

---

## Acceptance Criteria

1. **Pure Passthrough**: Client never echoes input locally
2. **Raw Bytes**: Control characters (0x03, 0x04, etc.) sent as-is
3. **PTY Authority**: Server PTY handles all echo & signals
4. **Simple Protocol**: `Input { data: Vec<u8> }` instead of complex parsing

---

## Files to Change

| File | Change | Effort |
|------|--------|--------|
| `crates/core/src/types/message.rs` | Add Input variant | 5min |
| `crates/cli_client/src/main.rs` | Use Input, remove String conversion | 20min |
| `crates/hostagent/src/quic_server.rs` | Handle Input message | 15min |
| `crates/mobile_bridge/src/quic_client.rs` | Add Input handler (fix breaking change) | 15min |

**Total**: ~1 hour 5min

---

## Success Metrics

- All test cases pass
- Ctrl+C works in iTerm2 (not just VSCode)
- No display corruption
- Clean git history
