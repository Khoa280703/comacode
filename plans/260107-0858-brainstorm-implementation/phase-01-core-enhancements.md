---
title: "Phase 01: Core Enhancements"
description: "Version constants, strict handshake, snapshot resync message type"
status: completed
priority: P0
effort: 3h
phase: 01
created: 2026-01-07
---

## Objectives

Add protocol versioning, strict handshake validation, và snapshot resync capability.

## Tasks

### 1.1 Version Constants (30min)

**File**: `crates/core/src/lib.rs`

```rust
// Add to top of lib.rs
pub const PROTOCOL_VERSION: u32 = 1;
pub const APP_VERSION_STRING: &str = "0.1.0-mvp";
pub const SNAPSHOT_BUFFER_LINES: usize = 1000;
```

**Verification**:
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_constants_defined() {
        assert_eq!(PROTOCOL_VERSION, 1);
        assert!(APP_VERSION_STRING.starts_with("0.1.0"));
    }
}
```

### 1.2 Strict Handshake Protocol (1.5h)

**File**: `crates/core/src/types/message.rs`

**Dependencies** (thêm vào `crates/core/Cargo.toml`):
```toml
[dependencies]
serde = { version = "1.0", features = ["derive"] }
thiserror = "1.0"
```

**Changes**:
1. Update `NetworkMessage::Hello` variant:
```rust
#[derive(Serialize, Deserialize, Debug, Clone)]
Hello {
    protocol_version: u32,  // MUST match PROTOCOL_VERSION
    app_version: String,     // For logging only
    capabilities: u32,
    auth_token: String,      // 32-byte token (empty in Phase 1, used in Phase 3)
}
```

2. Add handshake validation:
```rust
impl NetworkMessage {
    pub fn hello(token: String) -> Self {  // Nhận token từ đầu (empty trong Phase 1)
        Self::Hello {
            protocol_version: crate::PROTOCOL_VERSION,
            app_version: crate::APP_VERSION_STRING.to_string(),
            capabilities: 0,
            auth_token: token,
        }
    }

    pub fn validate_handshake(&self) -> Result<(), CoreError> {
        match self {
            NetworkMessage::Hello { protocol_version, .. } => {
                if *protocol_version == crate::PROTOCOL_VERSION {
                    Ok(())
                } else {
                    Err(CoreError::ProtocolVersionMismatch {
                        expected: crate::PROTOCOL_VERSION,
                        got: *protocol_version,
                    })
                }
            }
            _ => Err(CoreError::InvalidHandshake),
        }
    }
}
```

3. Add error variant to `crates/core/src/error.rs`:
```rust
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    // ... existing variants ...

    #[error("Protocol version mismatch: expected {expected}, got {got}")]
    ProtocolVersionMismatch { expected: u32, got: u32 },

    #[error("Invalid handshake message")]
    InvalidHandshake,
}
```

**Usage Example** (hostagent):
```rust
// On connection
let first_msg = recv_message().await?;
first_msg.validate_handshake()?;  // Disconnect if mismatch
```

### 1.3 Snapshot Resync Message Type (1h)

**File**: `crates/core/src/types/message.rs`

**Add new variants**:
```rust
pub enum NetworkMessage {
    // ... existing variants ...

    /// Request full terminal snapshot (client → host)
    RequestSnapshot,

    /// Full terminal snapshot response (host → client)
    /// Dùng Vec<u8> để an toàn với binary data, ANSI codes, invalid UTF-8
    Snapshot {
        /// Raw terminal data (scrollback + screen gom lại)
        data: Vec<u8>,
        /// Terminal size khi snapshot
        rows: u16,
        cols: u16,
    },
}
```

**Implementation**:
```rust
impl NetworkMessage {
    pub fn request_snapshot() -> Self {
        Self::RequestSnapshot
    }

    pub fn snapshot(data: Vec<u8>, rows: u16, cols: u16) -> Self {
        Self::Snapshot { data, rows, cols }
    }
}
```

**Add Terminal trait method** (`crates/core/src/terminal/traits.rs`):
```rust
pub trait Terminal {
    // ... existing methods ...

    /// Get current terminal state for snapshot
    /// Returns (raw bytes, rows, cols) for maximum compatibility
    fn get_snapshot(&self) -> Result<(Vec<u8>, u16, u16), CoreError>;
}
```

## Testing Strategy

**Manual Test**:
1. Start host với `PROTOCOL_VERSION = 1`
2. Connect client với `PROTOCOL_VERSION = 2` → expect disconnect
3. Request snapshot during active session → verify buffer size

**Acceptance Criteria**:
- ✅ Version constants accessible from all crates
- ✅ Handshake fails on version mismatch
- ✅ Snapshot message serializable via Postcard
- ✅ MockTerminal implements `get_snapshot()`

## Dependencies

- None (foundation phase)

## Blocked By

- None

## Notes

- Keep version checking strict (no semver ranges)
- Snapshot buffer size (1000 lines) có thể tune ở Phase 02
- Handshake timeout: 5s (define in Phase 03)
