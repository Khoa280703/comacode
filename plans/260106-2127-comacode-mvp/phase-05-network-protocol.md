---
title: "Phase 05: Network Protocol (QUIC)"
description: "Implement reliable QUIC protocol for terminal I/O using Quinn's built-in features"
status: completed
priority: P0
effort: 6h
branch: main
tags: [quic, network, protocol, rust]
created: 2026-01-06
updated: 2026-01-07
completed: 2026-01-08
---

# Phase 05: Network Protocol (QUIC)

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 04](./phase-04-mobile-app.md)
- **Revised:** 2026-01-07 - Removed over-engineered flow control, clarified migration vs reconnect

## Overview
Implement QUIC protocol layer for terminal communication using Quinn's built-in features (flow control, migration). **Do NOT reinvent what Quinn already provides.**

## Key Insights
- ✅ Quinn has built-in flow control (connection + stream level) - USE IT
- ✅ Quinn supports connection migration (WiFi ↔ LTE) - CONFIGURE IT
- ✅ Application-level backpressure: let `write_all()` await → stops PTY read → natural backpressure
- ⚠️ Migration ≠ Reconnect - different concepts
- ✅ Create `crates/core/src/transport/` as shared library for mobile_bridge and cli_client

## Already Done (Don't Reimplement)

| Component | Status | Location |
|-----------|--------|----------|
| MessageCodec | ✅ Done | `crates/core/src/protocol/codec.rs` |
| NetworkMessage | ✅ Done | `crates/core/src/types/message.rs` |
| Quinn handshake | ✅ Done | `quic_client.rs`, `quic_server.rs` |
| TOFU verification | ✅ Done | `TofuVerifier` |

## Requirements
- Stream pumps: PTY ↔ QUIC (bidirectional)
- QUIC config: migration enabled, proper timeout
- Heartbeat: Ping/Pong with timeout detection
- Reconnect: Exponential backoff for lost connections
- Core library: Shared between mobile_bridge and cli_client

## Architecture
```
crates/core/src/transport/          ← NEW - Shared library
├── mod.rs                           → configure_client(), configure_server()
├── stream.rs                        → pump_pty_to_quic(), pump_quic_to_pty()
├── heartbeat.rs                     → spawn_heartbeat(), detect timeout
└── reconnect.rs                     → exponential backoff reconnect

crates/mobile_bridge/                ← Consumer
└── src/quic_client.rs               → Uses transport library

crates/cli_client/                   ← Consumer
└── src/main.rs                      → Uses transport library
```

## Implementation Steps

### Step 1: QUIC Configuration (1h)

**File:** `crates/core/src/transport/mod.rs`

```rust
use quinn::{ClientConfig, ServerConfig, TransportConfig};
use quinn::crypto::rustls::QuicClientConfig;
use rustls::ClientConfig as RustlsConfig;
use std::sync::Arc;
use std::time::Duration;

/// Configure QUIC client with proper settings
pub fn configure_client(
    crypto_config: Arc<QuicClientConfig>,
) -> ClientConfig {
    let mut transport = TransportConfig::default();

    // CRITICAL: Enable QUIC migration (WiFi ↔ 4G switch)
    transport.disable_active_migration(false);

    // Timeout 30s for elevator/tunnel scenarios
    transport.max_idle_timeout(
        Some(Duration::from_secs(30).try_into().unwrap())
    );

    // Keep-alive interval
    transport.keep_alive_interval(Some(Duration::from_secs(5)));

    let mut config = ClientConfig::new(crypto_config);
    config.transport_config(Arc::new(transport));
    config
}

/// Configure QUIC server
pub fn configure_server(
    cert: Vec<CertificateDer<'static>>,
    key: PrivateKeyDer<'static>,
) -> Result<ServerConfig> {
    let mut transport = TransportConfig::default();
    transport.max_idle_timeout(
        Some(Duration::from_secs(30).try_into().unwrap())
    );
    transport.keep_alive_interval(Some(Duration::from_secs(5)));

    let mut config = ServerConfig::with_single_cert(cert, key)?;
    config.transport_config(Arc::new(transport));
    Ok(config)
}
```

**Tasks:**
- [ ] Create `crates/core/src/transport/mod.rs`
- [ ] Implement `configure_client()` with migration enabled
- [ ] Implement `configure_server()`
- [ ] Export from `crates/core/src/lib.rs`

---

### Step 2: Stream Pumps (2h) ← **PRIORITY**

**File:** `crates/core/src/transport/stream.rs`

```rust
use quinn::{SendStream, RecvStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use crate::protocol::MessageCodec;
use crate::types::NetworkMessage;
use crate::Result;

/// Pump data from PTY to QUIC stream
///
/// This is the CRITICAL function for terminal I/O.
/// Quinn's write_all() automatically handles backpressure:
/// - When network is slow, write_all() awaits
/// - Loop stops → no more PTY reads → natural backpressure
pub async fn pump_pty_to_quic<R>(
    mut pty: R,
    mut send: SendStream,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
{
    let mut buf = vec![0u8; 8192];

    loop {
        let n = pty.read(&mut buf).await?;
        if n == 0 { break; } // EOF

        // Encode as NetworkMessage FIRST (do NOT send raw bytes!)
        // MessageCodec already handles length prefixing
        let msg = NetworkMessage::Event(
            TerminalEvent::Output { data: buf[..n].to_vec() }
        );
        let encoded = MessageCodec::encode(&msg)?;

        // Send ONCE - Quinn handles flow control automatically
        send.write_all(&encoded).await?;
    }

    send.finish().await?;
    Ok(())
}

/// Pump data from QUIC stream to PTY
pub async fn pump_quic_to_pty<W>(
    mut recv: RecvStream,
    mut pty: W,
) -> Result<()>
where
    W: AsyncWriteExt + Unpin + Send,
{
    let mut len_buf = [0u8; 4];

    loop {
        // Read length prefix
        recv.read_exact(&mut len_buf).await?;
        let len = u32::from_be_bytes(len_buf) as usize;

        // Read payload
        let mut data = vec![0u8; len];
        recv.read_exact(&mut data).await?;

        // Decode message
        let msg = MessageCodec::decode(&data)?;

        match msg {
            NetworkMessage::Command(cmd) => {
                // Write to PTY
                pty.write_all(cmd.text.as_bytes()).await?;
            }
            NetworkMessage::Resize { rows, cols } => {
                // Handle resize
                // pty.resize(rows, cols)?;
            }
            _ => {}
        }
    }

    Ok(())
}

/// Bidirectional stream pump
pub async fn bidirectional_pump<R, W>(
    pty_reader: R,
    pty_writer: W,
    send: SendStream,
    recv: RecvStream,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
    W: AsyncWriteExt + Unpin + Send,
{
    let pty_task = tokio::spawn(pump_pty_to_quic(pty_reader, send));
    let quic_task = tokio::spawn(pump_quic_to_pty(recv, pty_writer));

    tokio::select! {
        r = pty_task => r??,
        r = quic_task => r??,
    }

    Ok(())
}
```

**Tasks:**
- [ ] Create `crates/core/src/transport/stream.rs`
- [ ] Implement `pump_pty_to_quic()`
- [ ] Implement `pump_quic_to_pty()`
- [ ] Implement `bidirectional_pump()`
- [ ] Add tests with mock streams

---

### ~~Step 3: Flow Control~~ → **DELETED**

**Reason:** Quinn has built-in flow control (connection + stream level).

**What was removed:**
- ~~`FlowController` struct~~ - Not needed
- ~~`can_send()`, `on_sent()`, `on_ack()`~~ - Quinn handles this
- ~~Window size tracking~~ - Quinn's BBR/Cubic handles congestion

**New approach: Application-level backpressure**
```rust
// Just write - Quinn handles the rest
send.write_all(&data).await?;

// When network is slow, this awaits
// → Loop stops
// → PTY read stops
// → Natural backpressure ✅
```

**Tasks:** (All deleted - use Quinn's built-in)

---

### Step 3: Heartbeat & Timeout Detection (1h)

**File:** `crates/core/src/transport/heartbeat.rs`

```rust
use quinn::SendStream;
use tokio::time::{interval, Duration, Instant};
use crate::protocol::MessageCodec;
use crate::types::NetworkMessage;
use crate::CoreError;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

pub struct Heartbeat {
    last_activity: Arc<AtomicU64>,
    timeout: Duration,
}

impl Heartbeat {
    pub fn new(timeout: Duration) -> Self {
        Self {
            last_activity: Arc::new(AtomicU64::new(
                Instant::now().elapsed().as_secs()
            )),
            timeout,
        }
    }

    /// Spawn heartbeat task
    /// FIXED: Receives shared Arc from outside, simplified timeout logic
    pub fn spawn(
        mut send: SendStream,
        interval: Duration,
        timeout: Duration,
        last_activity: Arc<AtomicU64>,
    ) -> tokio::task::JoinHandle<std::result::Result<(), CoreError>> {
        tokio::spawn(async move {
            let mut ticker = interval(interval);

            loop {
                ticker.tick().await;

                // ✅ CORRECT LOGIC: Compare current timestamp with last activity timestamp
                // Both are seconds since app start - simple subtraction works
                let current_secs = Instant::now().elapsed().as_secs();
                let last_secs = last_activity.load(Ordering::Relaxed);

                // Calculate time since last activity
                let idle_secs = current_secs.saturating_sub(last_secs);

                if idle_secs > timeout.as_secs() {
                    tracing::error!("Heartbeat timeout! Last activity was {}s ago", idle_secs);
                    return Err(CoreError::Timeout);
                }

                // Send ping
                let msg = NetworkMessage::ping();
                let encoded = MessageCodec::encode(&msg)?;
                send.write_all(&encoded).await?;

                tracing::debug!("Heartbeat sent, idle time: {}s", idle_secs);
            }
        })
    }

    /// Call this when receiving any data (updates shared state with current timestamp)
    pub fn record_activity(&self) {
        self.last_activity.store(
            Instant::now().elapsed().as_secs(),
            Ordering::Relaxed
        );
    }

    /// Get shared Arc for passing to spawn()
    pub fn shared_activity(&self) -> Arc<AtomicU64> {
        self.last_activity.clone()
    }
}
```

**Tasks:**
- [ ] Create `crates/core/src/transport/heartbeat.rs`
- [ ] Implement `Heartbeat::spawn()`
- [ ] Implement timeout detection
- [ ] Add `record_activity()` hook

---

### Step 4: Reconnection Logic (2h)

**File:** `crates/core/src/transport/reconnect.rs`

```rust
use quinn::{Endpoint, Connection};
use std::time::Duration;
use tokio::time::sleep;

pub struct ReconnectConfig {
    pub max_backoff: Duration,
    pub initial_backoff: Duration,
    pub max_attempts: Option<usize>,
}

impl Default for ReconnectConfig {
    fn default() -> Self {
        Self {
            max_backoff: Duration::from_secs(30),
            initial_backoff: Duration::from_secs(1),
            max_attempts: Some(10),
        }
    }
}

/// Attempt reconnection with exponential backoff
pub async fn reconnect_with_backoff(
    endpoint: &Endpoint,
    host: &str,
    port: u16,
    config: ReconnectConfig,
) -> Result<Connection> {
    let mut backoff = config.initial_backoff;
    let mut attempt = 0;

    loop {
        attempt += 1;

        // Try to connect
        let addr = format!("{}:{}", host, port).parse()?;
        let connecting = endpoint.connect(addr, "comacode-host")?;

        match connecting.await {
            Ok(conn) => {
                tracing::info!("Reconnected after {} attempts", attempt);
                return Ok(conn);
            }
            Err(e) => {
                if let Some(max) = config.max_attempts {
                    if attempt >= max {
                        return Err(Error::MaxReconnectAttemptsReached);
                    }
                }

                tracing::warn!("Reconnect attempt {} failed: {}, retrying in {:?}",
                    attempt, e, backoff);

                sleep(backoff).await;

                // Exponential backoff
                backoff = std::cmp::min(backoff * 2, config.max_backoff);
            }
        }
    }
}
```

**Tasks:**
- [ ] Create `crates/core/src/transport/reconnect.rs`
- [ ] Implement `reconnect_with_backoff()`
- [ ] Add `ReconnectConfig`
- [ ] Integrate with client disconnect detection

---

## Updated Todo List

- [ ] Step 1: Create `crates/core/src/transport/mod.rs`
- [ ] Step 1: Implement `configure_client()` with migration
- [ ] Step 1: Implement `configure_server()`
- [ ] Step 2: Create `crates/core/src/transport/stream.rs`
- [ ] Step 2: Implement `pump_pty_to_quic()` ← CRITICAL
- [ ] Step 2: Implement `pump_quic_to_pty()` ← CRITICAL
- [ ] Step 2: Implement `bidirectional_pump()`
- [ ] Step 3: Create `crates/core/src/transport/heartbeat.rs`
- [ ] Step 3: Implement heartbeat spawn logic
- [ ] Step 4: Create `crates/core/src/transport/reconnect.rs`
- [ ] Step 4: Implement exponential backoff
- [ ] Update `quic_client.rs` to use transport library
- [ ] Update `quic_server.rs` to use transport config
- [ ] Add integration tests

---

## Success Criteria

| Criteria | Test Method |
|----------|-------------|
| Commands reach server | Type `ls`, see output on PTY |
| Output streams to client | Run script, see output on phone |
| Reconnect works | Kill network, restore, verify reconnect |
| Migration works | WiFi ↔ 4G switch (manual test) |
| Latency <100ms | Ping timestamp diff |
| Backpressure works | Flood output, verify no OOM |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ~~Double buffering~~ | Low | High | ~~DELETED~~ - Using Quinn's flow control |
| QUIC blocked by firewall | High | High | Document UDP port requirement |
| NAT timeout drops conn | Medium | Medium | 30s timeout + 5s keep-alive |
| Stream closure race | Low | Medium | Proper error handling in pumps |
| Reconnect spam | Low | Low | Max attempts cap |

---

## Changes from Original Plan

| Aspect | Original | Revised | Reason |
|--------|----------|---------|--------|
| **Effort** | 10h | 6h | Removed flow control step |
| **Flow Control** | Custom `FlowController` | Use Quinn's built-in | Avoid double buffering |
| **Migration** | Unclear | `disable_active_migration(false)` | Proper QUIC migration |
| **Architecture** | Unclear | `crates/core/src/transport/` library | Shared between clients |
| **Step 3** | Flow Control | ~~DELETED~~ | Quinn handles it |

---

## Related Code Files

| File | Purpose |
|------|---------|
| `crates/core/src/transport/mod.rs` | NEW - Config helpers |
| `crates/core/src/transport/stream.rs` | NEW - Stream pumps |
| `crates/core/src/transport/heartbeat.rs` | NEW - Heartbeat |
| `crates/core/src/transport/reconnect.rs` | NEW - Reconnect |
| `crates/core/src/protocol/codec.rs` | ✅ EXISTS - MessageCodec |
| `crates/core/src/types/message.rs` | ✅ EXISTS - NetworkMessage |
| `crates/mobile_bridge/src/quic_client.rs` | UPDATE - Use transport lib |
| `crates/hostagent/src/quic_server.rs` | UPDATE - Use transport config |

---

## Next Steps

After Phase 05 complete:
1. Integration test: Server + Client full flow
2. Update stub implementations in `quic_client.rs`
3. Test end-to-end with real devices
4. Proceed to [Phase 06: Flutter UI](./phase-06-flutter-ui.md) (to be created)

**Phase Structure (updated 2026-01-07):**
- Phase 05: Network Protocol (current)
- Phase 06: Flutter UI
- Phase 07: Discovery & Auth (was `phase-06-discovery-auth.md`)
- Phase 08: Production Hardening (was `phase-07-testing-deploy.md`)

See `docs/project-roadmap.md` for full roadmap.

---

## Resources

- [quinn documentation](https://docs.rs/quinn/)
- [QUIC RFC 9000](https://datatracker.ietf.org/doc/html/rfc9000)
- [Connection migration](https://datatracker.ietf.org/doc/html/rfc9000#section-9)
- **Report:** `plans/reports/brainstorming-260107-phase05-network-review-vi.md`
