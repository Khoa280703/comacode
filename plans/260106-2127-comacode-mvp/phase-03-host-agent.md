---
title: "Phase 03: Host Agent (PC Binary)"
description: "Standalone PC application that manages PTY and exposes terminal via QUIC"
status: pending
priority: P0
effort: 12h
branch: main
tags: [rust, pty, host, quic-server]
created: 2026-01-06
---

# Phase 03: Host Agent (PC Binary)

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 02](./phase-02-rust-core.md)

## Overview
Build the PC-side Rust binary that spawns PTY processes, manages terminal sessions, and exposes them via QUIC server.

## Key Insights
- `portable-pty` provides cross-platform PTY support
- QUIC server needs connection management
- Each client gets dedicated PTY session
- Graceful shutdown is critical (don't orphan processes)
- Logging essential for debugging

## Requirements
- Spawn PTY process (shell: bash/zsh/pwsh/cmd)
- Bidirectional PTY I/O
- QUIC server with TLS
- Session multiplexing (multiple clients)
- Process lifecycle management
- Signal handling (SIGTERM/SIGINT)
- Logging & telemetry

## Architecture
```
Host Agent
├── QUIC Server (quinn)
│   ├── Connection Manager
│   └── Stream Handler
├── Session Manager
│   ├── Session Map (ID -> PTY)
│   └── Cleanup Task
└── PTY Spawner (portable-pty)
    ├── Shell detection
    └── Size control
```

## Implementation Steps

### Step 1: PTY Integration (3h)
```rust
// crates/host_agent/src/pty.rs
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use comacode_core::terminal::Terminal;

pub struct PtySession {
    pty: Box<dyn portable_pty::MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send>,
    rx: tokio::sync::mpsc::Receiver<Vec<u8>>,
}

impl PtySession {
    pub fn spawn(shell: Option<String>) -> Result<Self> {
        let pty_system = native_pty_system();
        let pty_pair = pty_system.openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })?;

        let shell_cmd = shell.unwrap_or_else(|| {
            if cfg!(windows) { "cmd.exe".to_string() }
            else { std::env::var("SHELL").unwrap_or("bash".into()) }
        });

        let mut cmd = CommandBuilder::new(shell_cmd);
        let child = pty_pair.slave.spawn_command(cmd)?;

        let reader = pty_pair.reader.try_clone_reader()?;
        let (tx, rx) = tokio::sync::mpsc::channel(100);

        // Spawn reader task
        tokio::spawn(async move {
            let mut buf = [0u8; 8192];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        let _ = tx.send(buf[..n].to_vec()).await;
                    }
                    Err(_) => break,
                }
            }
        });

        Ok(Self { pty: pty_pair.master, child, rx })
    }
}
```

**Tasks**:
- [ ] Add `portable-pty` dependency
- [ ] Detect default shell per platform
- [ ] Implement PTY spawning logic
- [ ] Add async reader task
- [ ] Handle PTY resize
- [ ] Test on Windows/macOS/Linux

### Step 2: Session Manager (2h)
```rust
// crates/host_agent/src/session.rs
use tokio::sync::RwLock;
use std::sync::Arc;
use std::collections::HashMap;

pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<u64, PtySession>>>,
    next_id: Arc<std::sync::atomic::AtomicU64>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: Default::default(),
            next_id: Arc::new(1.into()),
        }
    }

    pub async fn create_session(&self, shell: Option<String>) -> Result<u64> {
        let id = self.next_id.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let session = PtySession::spawn(shell)?;
        self.sessions.write().await.insert(id, session);
        Ok(id)
    }

    pub async fn get_session(&self, id: u64) -> Option<PtySession> {
        // Return handle or clone
    }

    pub async fn cleanup_session(&self, id: u64) -> Result<()> {
        let mut sessions = self.sessions.write().await;
        if let Some(mut session) = sessions.remove(&id) {
            session.kill().await?;
        }
        Ok(())
    }
}
```

**Tasks**:
- [ ] Implement session storage
- [ ] Add session lifecycle methods
- [ ] Implement cleanup task (reap dead sessions)
- [ ] Add session timeout (auto-close after inactivity)
- [ ] Write tests for concurrent sessions

### Step 3: QUIC Server Setup (3h)
```rust
// crates/host_agent/src/quic_server.rs
use quinn::{Endpoint, ServerConfig};
use rustls::Certificate;

pub struct QuicServer {
    endpoint: Endpoint,
    session_mgr: Arc<SessionManager>,
}

impl QuicServer {
    pub async fn new(cert: Certificate, key: PrivateKey) -> Result<Self> {
        let mut cfg = ServerConfig::with_single_cert(vec![cert], key)?;
        cfg.transport = Arc::get_mut(&mut cfg.transport)
            .unwrap()
            .max_concurrent_uni_streams(0_u8.into()); // Use bi-directional only

        let endpoint = Endpoint::new(Default::default(), Some(cfg), ())?;
        Ok(Self { endpoint, session_mgr: Arc::new(SessionManager::new()) })
    }

    pub async fn run(&self) -> Result<()> {
        while let Some(conn) = self.endpoint.accept().await {
            let session_mgr = self.session_mgr.clone();
            tokio::spawn(async move {
                if let Ok(e) = Self::handle_connection(conn, session_mgr).await {
                    eprintln!("Connection error: {:?}", e);
                }
            });
        }
        Ok(())
    }

    async fn handle_connection(
        connecting: quinn::Connecting,
        session_mgr: Arc<SessionManager>,
    ) -> Result<()> {
        let conn = connecting.await?;
        // Handle streams, create session, etc.
        Ok(())
    }
}
```

**Tasks**:
- [ ] Generate self-signed TLS cert for MVP
- [ ] Configure QUIC transport (keep-alive, idle timeout)
- [ ] Implement connection handler
- [ ] Add bi-directional stream handling
- [ ] Test QUIC handshake with client

### Step 4: Message Handler (2h)
```rust
// crates/host_agent/src/handler.rs
use comacode_core::{protocol::codec::MessageCodec, types::NetworkMessage};

async fn handle_stream(
    mut stream: quinn::SendStream,
    mut recv: quinn::RecvStream,
    session: &PtySession,
) -> Result<()> {
    // Message receive loop
    let mut read_buf = vec![0u8; 1024];

    loop {
        let n = recv.read(&mut read_buf).await?;
        if n == 0 { break; }

        let msg = MessageCodec::decode(&read_buf[..n])?;

        match msg {
            NetworkMessage::Command(cmd) => {
                session.write(cmd.text.as_bytes()).await?;
            }
            NetworkMessage::Heartbeat => {
                // Respond with heartbeat
                let ack = MessageCodec::encode(&NetworkMessage::Heartbeat)?;
                stream.write_all(&ack).await?;
            }
            _ => {}
        }
    }

    Ok(())
}
```

**Tasks**:
- [ ] Implement message parsing loop
- [ ] Route commands to PTY
- [ ] Forward PTY output to stream
- [ ] Handle heartbeat/ping-pong
- [ ] Add error recovery

### Step 5: CLI & Service Mode (2h)
```rust
// crates/host_agent/src/main.rs
#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Setup logging
    tracing_subscriber::fmt()
        .with_max_level(args.log_level)
        .init();

    // Generate/load TLS cert
    let (cert, key) = load_or_generate_cert()?;

    // Start server
    let server = QuicServer::new(cert, key).await?;
    server.run().await?;

    Ok(())
}
```

**Tasks**:
- [ ] Add `clap` for CLI argument parsing
- [ ] Implement `--port`, `--log-level` flags
- [ ] Add systemd service integration (Linux)
- [ ] Add macOS launchd support
- [ ] Create Windows service wrapper
- [ ] Add graceful shutdown handling

## Todo List
- [ ] Add `portable-pty` dependency
- [ ] Implement PTY spawner
- [ ] Build session manager
- [ ] Set up QUIC server
- [ ] Generate TLS certificates
- [ ] Implement message handler
- [ ] Add CLI with clap
- [ ] Test on all platforms
- [ ] Add service integration
- [ ] Write integration tests

## Success Criteria
- Spawns PTY on all platforms (Win/Mac/Linux)
- QUIC connection established from client
- Commands execute and output streams back
- Multiple concurrent sessions supported
- Clean process termination (no orphans)
- Runs as system service

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| PTY Windows permissions | Medium | High | Test early, document requirements |
| QUIC firewall blocking | High | Medium | Document ports, provide UPnP helper |
| Shell detection fails | Low | Low | Fallback to hardcoded list |
| Process orphaning | Medium | High | Implement robust cleanup, test signals |

## Security Considerations
- TLS certificates for encryption (self-signed in MVP)
- No authentication yet (Phase 6)
- Rate limit PTY writes (prevent DoS)
- Sanitize PTY input (no ANSI escapes in commands)
- Chroot/jail if possible (Phase 2)

## Related Code Files
- `/crates/host_agent/src/main.rs` - Entry point
- `/crates/host_agent/src/pty.rs` - PTY management
- `/crates/host_agent/src/quic_server.rs` - Network server
- `/crates/host_agent/src/session.rs` - Session lifecycle

## Next Steps
After host agent runs locally, proceed to [Phase 04: Mobile App](./phase-04-mobile-app.md) to build the client.

## Resources
- [portable-ty docs](https://docs.rs/portable-pty/)
- [quinn examples](https://github.com/quinn-rs/quinn/tree/main/quinn/examples)
- [Rust service patterns](https://docs.rs/sysinfo/)
