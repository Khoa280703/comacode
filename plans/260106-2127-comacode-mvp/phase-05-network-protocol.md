---
title: "Phase 05: Network Protocol (QUIC)"
description: "Implement reliable QUIC protocol with zero-latency design for terminal I/O"
status: pending
priority: P0
effort: 10h
branch: main
tags: [quic, network, protocol, rust]
created: 2026-01-06
---

# Phase 05: Network Protocol (QUIC)

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 04](./phase-04-mobile-app.md)

## Overview
Implement QUIC protocol layer for zero-latency terminal communication. Handles connection management, multiplexing, and reliable transport.

## Key Insights
- QUIC eliminates TCP head-of-line blocking
- Separate streams for commands vs output
- 0-RTT connection resume for fast reconnect
- Keep-alive prevents NAT timeout
- Flow control prevents buffer bloat

## Requirements
- QUIC transport (quinn crate)
- Bidirectional streams per session
- Message framing (length-prefix)
- Flow control config
- Keep-alive/heartbeat
- Connection migration (WiFi → LTE)
- Graceful reconnection

## Architecture
```
Network Layer
├── QUIC Transport (quinn)
│   ├── Endpoint Management
│   └── Connection Pool
├── Stream Multiplexer
│   ├── Command Stream (high priority)
│   └── Output Stream (buffered)
└── Message Framing
    ├── Length Prefix
    └── Checksum
```

## Implementation Steps

### Step 1: Transport Abstraction (2h)
```rust
// crates/core/src/transport/mod.rs
use quinn::{Endpoint, NewConnection};

pub struct QuicTransport {
    endpoint: Endpoint,
    connection: Option<quinn::Connection>,
}

impl QuicTransport {
    pub async fn connect(host: &str, port: u16) -> Result<Self> {
        let mut endpoint = Endpoint::default();
        endpoint.set_default_client_config(configure_client());

        let connecting = endpoint.connect(host, port)?;
        let connection = connecting.await?;

        Ok(Self {
            endpoint,
            connection: Some(connection),
        })
    }

    pub async fn open_stream(&self) -> Result<quinn::SendStream> {
        let conn = self.connection.as_ref().ok_or(Error::NotConnected)?;
        conn.open_uni().await.map_err(Into::into)
    }
}
```

**Tasks**:
- [ ] Define transport trait
- [ ] Configure QUIC parameters
- [ ] Implement connection factory
- [ ] Add connection state tracking
- [ ] Handle connection errors

### Step 2: Stream Management (2h)
```rust
// crates/core/src/transport/stream.rs
pub struct StreamManager {
    command_tx: quinn::SendStream,
    output_rx: quinn::RecvStream,
}

impl StreamManager {
    pub fn new(cmd_tx: quinn::SendStream, out_rx: quinn::RecvStream) -> Self {
        Self {
            command_tx: cmd_tx,
            output_rx: out_rx,
        }
    }

    pub async fn send_command(&mut self, cmd: TerminalCommand) -> Result<()> {
        let msg = NetworkMessage::Command(cmd);
        let encoded = MessageCodec::encode(&msg)?;

        // Frame: [length: u32 BE][data]
        let len = encoded.len() as u32;
        self.command_tx.write_all(&len.to_be_bytes()).await?;
        self.command_tx.write_all(&encoded).await?;

        Ok(())
    }

    pub async fn recv_output(&mut self) -> Result<TerminalEvent> {
        let mut len_buf = [0u8; 4];
        self.output_rx.read_exact(&mut len_buf).await?;
        let len = u32::from_be_bytes(len_buf) as usize;

        let mut data = vec![0u8; len];
        self.output_rx.read_exact(&mut data).await?;

        let msg = MessageCodec::decode(&data)?;
        match msg {
            NetworkMessage::Event(event) => Ok(event),
            _ => Err(Error::UnexpectedMessage),
        }
    }
}
```

**Tasks**:
- [ ] Implement message framing
- [ ] Add length prefixing
- [ ] Create stream pair abstraction
- [ ] Handle stream closure
- [ ] Add timeout for reads

### Step 3: Flow Control (2h)
```rust
// crates/core/src/transport/flow.rs
pub struct FlowController {
    window_size: u64,
    pending_bytes: usize,
    max_pending: usize,
}

impl FlowController {
    pub fn new(window_size: u64) -> Self {
        Self {
            window_size,
            pending_bytes: 0,
            max_pending: 64 * 1024, // 64KB
        }
    }

    pub fn can_send(&self, len: usize) -> bool {
        self.pending_bytes + len <= self.max_pending
    }

    pub fn on_sent(&mut self, len: usize) {
        self.pending_bytes += len;
    }

    pub fn on_ack(&mut self, len: usize) {
        self.pending_bytes = self.pending_bytes.saturating_sub(len);
    }
}
```

**Tasks**:
- [ ] Configure QUIC flow control
- [ ] Implement backpressure
- [ ] Add window size tracking
- [ ] Rate limit command sends
- [ ] Test under saturation

### Step 4: Heartbeat & Keep-Alive (2h)
```rust
// crates/core/src/transport/heartbeat.rs
use tokio::time::{interval, Duration};

pub struct Heartbeat {
    interval: Duration,
    last_rx: std::time::Instant,
    timeout: Duration,
}

impl Heartbeat {
    pub fn new(interval: Duration, timeout: Duration) -> Self {
        Self {
            interval,
            last_rx: std::time::Instant::now(),
            timeout,
        }
    }

    pub async fn run(&mut self, mut tx: quinn::SendStream) -> Result<()> {
        let mut ticker = interval(self.interval);

        loop {
            ticker.tick().await;

            if self.last_rx.elapsed() > self.timeout {
                return Err(Error::Timeout);
            }

            let msg = MessageCodec::encode(&NetworkMessage::Heartbeat)?;
            tx.write_all(&msg).await?;
        }
    }

    pub fn on_activity(&mut self) {
        self.last_rx = std::time::Instant::now();
    }
}
```

**Tasks**:
- [ ] Add heartbeat interval (5s)
- [ ] Detect connection timeout
- [ ] Send periodic pings
- [ ] Measure RTT
- [ ] Trigger reconnect on timeout

### Step 5: Connection Migration (2h)
```rust
// crates/core/src/transport/migrate.rs
pub struct ConnectionMigrator {
    transport: QuicTransport,
    backoff: Duration,
}

impl ConnectionMigrator {
    pub async fn maintain_connection(&mut self) -> Result<()> {
        loop {
            tokio::time::sleep(self.backoff).await;

            if !self.transport.is_connected() {
                tracing::info!("Connection lost, attempting reconnect...");
                self.transport.reconnect().await?;

                // Resume session
                self.transport.resume_session().await?;
            }

            self.backoff = std::cmp::min(self.backoff * 2, Duration::from_secs(30));
        }
    }
}
```

**Tasks**:
- [ ] Implement exponential backoff
- [ ] Add reconnect logic
- [ ] Session state restoration
- [ ] NAT rebinding support
- [ ] Test network switching

## Todo List
- [ ] Add quinn dependency
- [ ] Implement transport abstraction
- [ ] Create stream manager
- [ ] Add message framing
- [ ] Configure flow control
- [ ] Implement heartbeat
- [ ] Add reconnect logic
- [ ] Test network switching
- [ ] Benchmark throughput
- [ ] Add metrics/logging

## Success Criteria
- End-to-end latency <100ms (LAN)
- Commands arrive in order
- No data loss on disconnect
- Auto-reconnect within 5s
- Throughput >1MB/s (output)
- NAT traversal works

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| QUIC blocked by firewall | High | High | Document ports, offer TCP fallback |
| NAT timeout drops conn | Medium | Medium | Aggressive keep-alive (5s) |
| Stream exhaustion | Low | Medium | Limit concurrent streams |
| Packet reordering | Low | Low | QUIC handles natively |

## Security Considerations
- TLS 1.3 required (QUIC built-in)
- Certificate validation
- No plaintext fallback
- ALPN protocol negotiation
- Secure handshake

## Related Code Files
- `/crates/core/src/transport/` - Transport layer
- `/crates/host_agent/src/quic_server.rs` - Server endpoint
- `/crates/mobile_bridge/src/api.rs` - Client exports

## Next Steps
After network stable, proceed to [Phase 06: Discovery & Auth](./phase-06-discovery-auth.md) for UX polish.

## Resources
- [quinn repo](https://github.com/quinn-rs/quinn)
- [QUIC RFC](https://datatracker.ietf.org/doc/html/rfc9000)
- [Connection migration](https://datatracker.ietf.org/doc/html/rfc9000#section-9)
