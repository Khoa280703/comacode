---
title: "Phase 02: Shared Rust Core"
description: "Build shared business logic, types, and utilities for cross-platform use"
status: completed
priority: P0
effort: 8h
branch: main
tags: [rust, core, shared-logic]
created: 2026-01-06
completed: 2026-01-06
---

# Phase 02: Shared Rust Core

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 01](./phase-01-project-setup.md)

## Overview
Implement shared Rust code used by both mobile (via FFI) and host agent. Domain models, protocol handling, terminal abstraction.

## Key Insights
- Shared types prevent serialization bugs between platforms
- Protocol logic in Rust ensures consistency
- Postcard serialization for efficiency
- Async/await for I/O operations

## Requirements
- Shared domain types (commands, events, state)
- Message serialization (Postcard)
- Terminal abstraction traits
- Protocol state machine
- Error handling types
- FFI-safe APIs

## Architecture
```
crates/core/
├── src/
│   ├── lib.rs              # Public API
│   ├── types/              # Domain models
│   │   ├── mod.rs
│   │   ├── command.rs      # TerminalCommand
│   │   ├── event.rs        # TerminalEvent
│   │   └── message.rs      # NetworkMessage
│   ├── protocol/           # QUIC protocol logic
│   │   ├── mod.rs
│   │   ├── codec.rs        # Postcard en/decode
│   │   └── state.rs        # ConnectionState
│   ├── terminal/           # PTY abstraction
│   │   ├── mod.rs
│   │   └── traits.rs       # Terminal trait
│   └── error.rs            # Error types
└── Cargo.toml
```

## Implementation Steps

### Step 1: Domain Types (2h)
```rust
// src/types/command.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalCommand {
    pub id: u64,
    pub text: String,
    pub timestamp: u64,
}

// src/types/event.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TerminalEvent {
    Output { data: Vec<u8> },
    Error { message: String },
    Exit { code: i32 },
}

// src/types/message.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NetworkMessage {
    Hello { version: String },
    Command(TerminalCommand),
    Event(TerminalEvent),
    Heartbeat,
}
```

**Tasks**:
- [ ] Define `TerminalCommand` with keystroke/input
- [ ] Define `TerminalEvent` for output/errors
- [ ] Define `NetworkMessage` protocol
- [ ] Add Postcard derives
- [ ] Write unit tests for serialization

### Step 2: Protocol Codec (2h)
```rust
// src/protocol/codec.rs
use postcard::{from_bytes, to_allocvec};

pub struct MessageCodec;

impl MessageCodec {
    pub fn encode(msg: &NetworkMessage) -> Result<Vec<u8>, Error> {
        to_allocvec(msg).map_err(Into::into)
    }

    pub fn decode(buf: &[u8]) -> Result<NetworkMessage, Error> {
        from_bytes(buf).map_err(Into::into)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_roundtrip() {
        let msg = NetworkMessage::Heartbeat;
        let encoded = MessageCodec::encode(&msg).unwrap();
        let decoded = MessageCodec::decode(&encoded).unwrap();
        assert!(matches!(decoded, NetworkMessage::Heartbeat));
    }
}
```

**Tasks**:
- [ ] Implement `encode()` for NetworkMessage
- [ ] Implement `decode()` with error handling
- [ ] Add frame format (length prefix)
- [ ] Test roundtrip serialization
- [ ] Benchmark serialization speed

### Step 3: Terminal Abstraction (2h)
```rust
// src/terminal/traits.rs
use async_trait::async_trait;

#[async_trait]
pub trait Terminal: Send + Sync {
    async fn write(&mut self, data: &[u8]) -> Result<()>;
    async fn read(&mut self) -> Result<Vec<u8>>;
    fn resize(&mut self, rows: u16, cols: u16) -> Result<()>;
    async fn kill(&mut self) -> Result<()>;
}

// Mock implementation for mobile testing
pub struct MockTerminal;

#[async_trait]
impl Terminal for MockTerminal {
    async fn write(&mut self, data: &[u8]) -> Result<()> {
        Ok(())
    }
    // ... other methods
}
```

**Tasks**:
- [ ] Define `Terminal` trait
- [ ] Create `MockTerminal` for testing
- [ ] Document trait methods
- [ ] Add error types for terminal operations
- [ ] Write async unit tests

### Step 4: Error Handling (1h)
```rust
// src/error.rs
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("Serialization failed: {0}")]
    Serialization(#[from] postcard::Error),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Terminal error: {0}")]
    Terminal(String),
}

pub type Result<T> = std::result::Result<T, CoreError>;
```

**Tasks**:
- [ ] Define comprehensive error enum
- [ ] Add `thiserror` dependency
- [ ] Implement conversion traits
- [ ] Add error context helpers

### Step 5: FFI Bridge Layer (1h)
```rust
// crates/mobile_bridge/src/api.rs
use flutter_rust_bridge::frb;
use comacode_core::types::TerminalCommand;

#[frb(sync)]
pub fn create_command(text: String) -> TerminalCommand {
    TerminalCommand {
        id: chrono::Utc::now().timestamp_micros() as u64,
        text,
        timestamp: std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
    }
}

#[frb]
pub async fn encode_command(cmd: TerminalCommand) -> Result<Vec<u8>, String> {
    comacode_core::protocol::codec::MessageCodec::encode(
        &comacode_core::types::NetworkMessage::Command(cmd)
    ).map_err(|e| e.to_string())
}
```

**Tasks**:
- [ ] Add FFI exports for core types
- [ ] Expose serialization functions
- [ ] Document Dart API
- [ ] Generate Dart bindings
- [ ] Test FFI calls from Dart

## Todo List
- [ ] Create core crate structure
- [ ] Implement domain types
- [ ] Add Postcard serialization
- [ ] Build protocol codec
- [ ] Define terminal trait
- [ ] Add error handling
- [ ] Create FFI bridge functions
- [ ] Write comprehensive tests
- [ ] Document public API
- [ ] Benchmark serialization

## Success Criteria
- All types serialize/deserialize correctly
- FFI bridge generates valid Dart code
- Unit tests cover 80%+ of core logic
- No unsafe code (except FFI boundaries)
- Documentation for all public APIs

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Postcard compatibility | Low | Medium | Test cross-platform byte order |
| Async FFI complexity | Medium | High | Keep FFI sync, use channels for async |
| Type drift between FFI | Low | Medium | Use FRB codegen, version bindings |

## Security Considerations
- Validate all input on deserialization
- Limit message size (prevent OOM)
- Sanitize terminal input (prevent escape injection)
- Use timeouts on async operations

## Related Code Files
- `/crates/core/src/lib.rs` - Public API
- `/crates/core/src/types/` - Domain models
- `/crates/core/src/protocol/codec.rs` - Serialization
- `/crates/mobile_bridge/src/api.rs` - FFI exports

## Next Steps
After core is solid, proceed to [Phase 03: Host Agent](./phase-03-host-agent.md) to implement PC binary.

## Resources
- [Postcard docs](https://docs.rs/postcard/)
- [thiserror guide](https://docs.rs/thiserror/)
- [FRB async patterns](https://cjycode.com/q/async)
