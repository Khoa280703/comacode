---
title: "CLI Client Raw Mode TUI - SSH-like Experience"
description: "Implement raw mode passthrough for proper Ctrl+C handling and full TUI support"
status: pending
priority: P1
effort: 4-8h
issue: 0
branch: main
tags: [cli, tui, raw-mode, crossterm, ux]
created: 2026-01-08
---

# CLI Client Raw Mode TUI - SSH-like Experience

## Overview

Upgrade `cli_client` from line-mode to **raw mode passthrough** for true terminal experience.

**Current Problems**:
- Ctrl+C kills entire cli_client process
- Line-mode (`read_line()`) doesn't support vim/htop
- No dedicated "terminal box" UI

**Target**:
- Ctrl+C sends interrupt to remote server only
- Full ANSI support (colors, cursor, vim, htop)
- Clean screen when connected
- `/exit` to disconnect

---

## Solution Design

### Raw Mode Passthrough Architecture

```
User Terminal (iTerm2/VSCode)
        │
        ▼
┌─────────────────────────────────────┐
│      cli_client (crossterm)        │
│  ┌───────────────────────────────┐  │
│  │   Raw Mode Enabled            │  │
│  │   - No line buffering        │  │
│  │   - No local echo            │  │
│  │   - Pass through all keys    │  │
│  └───────────────────────────────┘  │
│                                     │
│  stdin ────────────────────┐         │
│                          │   │         │
│                          ▼   ▼         │
│                      ┌─────────┐      │
│                      │ tokio:: │      │
│                      │ select! │      │
│                      └─────────┘      │
│                          │   │         │
│                          ▼   ▼         │
│  stdout ◀─────────────────┘         │
└─────────────────────────────────────┘
        │       │ QUIC
        ▼       ▼
┌─────────────────────────────────────┐
│         hostagent (Server)          │
│  ┌───────────────────────────────┐  │
│  │         PTY                   │  │
│  │  - Receives raw bytes        │  │
│  │  - Ctrl+C = SIGINT to shell  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Key Changes from Current Implementation

| Aspect | Current (Line Mode) | New (Raw Mode) |
|--------|-------------------|----------------|
| Input | `read_line()` blocking | `read()` byte-by-byte |
| Echo | Local echo | Remote echo (from PTY) |
| Ctrl+C | Kills client | Sends 0x03 to server |
| ANSI | Parsed (breaks) | Passed through |
| Vim/Top | ❌ Doesn't work | ✅ Works |

---

## Implementation Steps

### Step 1: Add crossterm dependency (5min)

```toml
# crates/cli_client/Cargo.toml
[dependencies]
crossterm = "0.28"
```

### Step 2: Raw mode wrapper (30min)

Create `RawModeGuard` to ensure cleanup:

```rust
// crates/cli_client/src/raw_mode.rs
use crossterm::terminal;
use anyhow::Result;

pub struct RawModeGuard;

impl RawModeGuard {
    pub fn enable() -> Result<Self> {
        terminal::enable_raw_mode()?;
        Ok(Self)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        let _ = terminal::disable_raw_mode();
    }
}
```

### Step 3: Replace main loop (1.5h)

**Current code** (`crates/cli_client/src/main.rs:154-240`):
```rust
// Line mode - reads full lines
let stdin = tokio::io::stdin();
let mut reader = BufReader::new(stdin);
let mut line = String::new();

loop {
    reader.read_line(&mut line).await?;  // Blocking
    // ... process line
}
```

**New code**:
```rust
use std::io::{Read, Write};
use tokio::task::JoinSet;

// After handshake successful
println!("\x1b[2J\x1b[H"); // Clear screen, move cursor to top
println!("🖥️  Connected. Ctrl+C to interrupt, /exit to disconnect.\r\n");

let _guard = RawModeGuard::enable()?;

let mut tasks = JoinSet::new();

// Task 1: stdin → server
let mut send_clone = send.clone();
tasks.spawn(async move {
    let mut stdin = std::io::stdin();
    let mut buf = [0u8; 1024];

    loop {
        match stdin.read(&mut buf) {
            Ok(0) => break, // EOF (Ctrl+D)
            Ok(n) => {
                // CRITICAL FIX: Wrap in NetworkMessage before sending
                // Server expects MessageCodec, NOT raw bytes!
                let text = String::from_utf8_lossy(&buf[..n]).to_string();

                // Check for /exit command locally
                if text.trim() == "/exit" {
                    break;
                }

                // Wrap in Command and encode (MVP - use existing Command type)
                let cmd = NetworkMessage::Command(TerminalCommand::new(text.clone()));
                let encoded = MessageCodec::encode(&cmd)?;

                if send_clone.write_all(&encoded).await.is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    Ok::<(), anyhow::Error>(())
});

// Task 2: server → stdout
tasks.spawn(async move {
    let stdout = std::io::stdout();
    let mut stdout_lock = stdout.lock();
    let mut buf = vec![0u8; 8192];

    loop {
        match recv.read(&mut buf).await {
            Ok(Some(n)) => {
                // Decode MessageCodec first
                if let Ok(msg) = MessageCodec::decode(&buf[..n]) {
                    if let NetworkMessage::Event(event) = msg {
                        if let TerminalEvent::Output { data } = event {
                            // Write raw bytes to stdout
                            let _ = stdout_lock.write_all(&data);
                            let _ = stdout_lock.flush();
                        }
                    }
                }
            }
            Ok(None) => break,
            Err(_) => break,
        }
    }
});

// Wait for either task to complete
while tasks.join_next().await.is_some() {}

// Cleanup happens automatically via RawModeGuard::drop
```

### Step 4: Handle MessageCodec in raw mode (1h)

Current protocol wraps terminal output in `NetworkMessage::Event`. Need to:

1. Decode incoming messages
2. Extract raw bytes from `TerminalEvent::Output { data }`
3. Write to stdout

```rust
// Helper function
async fn forward_to_stdout(recv: &mut RecvStream) -> Result<()> {
    let mut buf = vec![0u8; 8192];
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();

    loop {
        let n = recv.read(&mut buf).await?.ok_or("EOF")?;
        if let Ok(msg) = MessageCodec::decode(&buf[..n]) {
            if let NetworkMessage::Event(TerminalEvent::Output { data }) = msg {
                lock.write_all(&data)?;
                lock.flush()?;
            }
        }
    }
}
```

### Step 5: Test & verify (1-2h)

Test sequence:
1. `pwd` → should show directory
2. `ls -la --color=auto` → should see colors
3. `vim` → should enter insert mode, edit, save/quit
4. `htop` → should display correctly
5. Ctrl+C during `sleep 10` → should cancel sleep, NOT disconnect

---

## File Changes Summary

| File | Change | Effort |
|------|--------|--------|
| `Cargo.toml` | Add crossterm | 5min |
| `src/main.rs` | Replace line-mode loop with raw mode passthrough | 2h |
| `src/raw_mode.rs` | NEW - RawModeGuard wrapper | 30min |

---

## Acceptance Criteria

- [ ] `/exit` command disconnects cleanly
- [ ] Ctrl+C during `sleep 10` cancels sleep only
- [ ] `vim` can edit, save, quit normally
- [ ] `htop` displays interactive UI correctly
- [ ] Terminal colors preserved (`ls --color=auto`)
- [ ] Terminal state restored after disconnect
- [ ] No garbage characters on screen

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Raw mode not restored | Terminal broken | Use `RawModeGuard` with `Drop` trait |
| MessageCodec overhead | Latency | Keep buffer size reasonable (8KB) |
| Deadlock | Hang | Timeout on read/write |
| Screen corruption | UX issue | Clear screen on connect, restore on exit |

---

## Dependencies

- `crossterm 0.28` - Raw terminal mode
- Existing: `tokio`, `comacode-core`, `quinn`

---

## Next Steps

1. Review this plan
2. Implement Step 1-3 (core raw mode)
3. Test with basic commands
4. Implement Step 4 (MessageCodec handling)
5. Full testing (vim, htop)
6. Update documentation

---

**Created**: 2026-01-08
**Estimate**: 4-8h total (3h core + 1-2h protocol + 1-2h testing + 1h polish)
