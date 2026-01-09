# Brainstorm Report: CLI Client TUI Mode with Raw Passthrough

**Date**: 2026-01-08
**Type**: UX Improvement - Terminal Interaction
**Status**: Ready for Implementation

---

## Problem Statement

### Current Issues
1. **Ctrl+C kills entire cli_client process** - When user presses Ctrl+C to cancel a running command, the whole connection drops
2. **No dedicated UI mode** - Commands are mixed with cli_client output, confusing
3. **Line-mode limitation** - Current `read_line()` approach doesn't support interactive programs (vim, top, htop)

### User Requirements
- Clear terminal when connected → enter dedicated "box" for interaction
- Ctrl+C should send interrupt to **remote server**, NOT kill local client
- Only `/exit` or explicit quit should disconnect
- Support full ANSI escape sequences (colors, cursor movement)
- Support interactive TUI programs (vim, htop, etc.)

---

## Evaluated Approaches

### ❌ Option 1: Full TUI with Custom Rendering (Ratatui)
**Approach**: Parse ANSI codes from server, render to custom TUI widgets

**Pros**:
- Full control over UI
- Can add custom overlays (status bar, command palette)

**Cons**:
- **Extremely complex** - Must write xterm-compatible ANSI parser
- **Breaks vim/htop** - These programs expect direct terminal control
- Reinventing the wheel
- 40-60 hours effort

**Verdict**: Over-engineering, wrong tool for the job

---

### ❌ Option 2: Custom Input Box with ANSI Display
**Approach**: Keep output as passthrough, add custom input line at bottom

**Pros**:
- Simpler than full TUI
- Preserves most ANSI output

**Cons**:
- Still complex to coordinate
- Screen resize issues
- Input/output synchronization problems
- 20-30 hours effort

**Verdict**: Middle ground with worst of both worlds

---

### ✅ Option 3: Raw Mode Passthrough (RECOMMENDED)
**Approach**: Use `crossterm` raw mode, pass input/output directly through

**Pros**:
- **Simple & Robust** - 4-8 hours implementation
- **Perfect ANSI support** - Terminal (iTerm2, Windows Terminal) handles rendering
- **Full TUI program support** - vim, htop, vim work natively
- **Just like SSH** - Familiar UX
- Ctrl+C = send 0x03 byte to server (standard behavior)

**Cons**:
- No custom UI overlays in MVP (can add later)
- Need proper cleanup on exit

**Verdict**: **Best solution** - YAGNI + KISS principles

---

## Recommended Solution: Raw Mode Passthrough

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    cli_client (Local)                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  stdin (raw)  ──────┐                                   │
│                        │   ┌─────────────────┐          │
│                        ├──▶│  crossterm      │          │
│                        │   │  Raw Mode      │          │
│  stdout (raw) ◀───────┘   └─────────────────┘          │
│           ▲                                               │
│           │                                               │
│           │    QUIC Network                              │
│           ▼                                               │
└───────────────────┐   ┌──────────────────────────────────┐
                    │   │        hostagent (Server)         │
                    │   ├──────────────────────────────────┤
                    │   │  ┌────────────────────────────┐  │
                    └───┼─▶│  PTY (psuedo-terminal)     │  │
                        │  └────────────────────────────┘  │
                        │                                   │
                        │  Input: 0x03 (Ctrl+C)            │
                        │  → Kills foreground process      │
                        │  → PTY stays alive               │
                        └───────────────────────────────────┘
```

### Key Implementation Points

#### 1. Raw Mode Setup
```rust
use crossterm::terminal::{enable_raw_mode, disable_raw_mode};

// After connect success
enable_raw_mode()?;
```

**What Raw Mode Does**:
- Disables line buffering (each key available immediately)
- Disables echo (server echoes back)
- Passes through all control characters (Ctrl+C, Ctrl+Z, etc.)

#### 2. Bidirectional Passthrough

```rust
// Task 1: Keyboard → Server
let input_task = tokio::spawn(async move {
    let mut stdin = tokio::io::stdin();
    let mut buf = [0u8; 1024];

    loop {
        match stdin.read(&mut buf).await {
            Ok(0) => break, // EOF
            Ok(n) => {
                // Send raw bytes to server
                // Ctrl+C = 0x03 byte, just pass through
                send.write_all(&buf[..n]).await?;
            }
            Err(_) => break,
        }
    }
});

// Task 2: Server → Screen
let output_task = tokio::spawn(async move {
    let mut stdout = tokio::io::stdout();
    let mut buf = [0u8; 8192];

    loop {
        match recv.read(&mut buf).await {
            Ok(Some(n)) => {
                // Write raw bytes (ANSI colors, cursor control)
                stdout.write_all(&buf[..n]).await?;
                stdout.flush().await?;
            }
            Ok(None) => break,
            Err(_) => break,
        }
    }
});
```

#### 3. Exit Handling

```rust
// Special sequence to exit: `/exit` command
// Or: Ctrl+D (EOF) on stdin

tokio::select! {
    _ = input_task => { /* User disconnected */ }
    _ = output_task => { /* Server closed */ }
}

// CRITICAL: Always restore terminal
disable_raw_mode()?;
println!("\r\n📡 Connection closed.");
```

#### 4. Ctrl+C Behavior

In raw mode:
- `Ctrl+C` = byte `0x03`
- Sent directly to server PTY
- PTY sends `SIGINT` to foreground process
- Client process ** unaffected**

---

## Implementation Plan

### Phase 1: Core Raw Mode (2-3h)
- [ ] Add `crossterm` dependency
- [ ] Implement raw mode enable/disable
- [ ] Bidirectional passthrough tasks
- [ ] Clean exit handling

### Phase 2: Protocol Adaptation (1-2h)
- [ ] Remove `read_line()` - use raw `read()`
- [ ] Handle `MessageCodec` wrapping
- [ ] Test with `pwd`, `ls`, `echo`

### Phase 3: Full TUI Support (1-2h)
- [ ] Test with `vim`
- [ ] Test with `htop`
- [ ] Test with `nano`
- [ ] ANSI color verification

### Phase 4: Polish (1h)
- [ ] `/exit` command detection
- [ ] Connection error handling
- [ ] Terminal cleanup verification

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Terminal not restored | HIGH | Use `defer` or `Drop` trait to ensure cleanup |
| Deadlock on half-close | Medium | Timeout on both directions |
| Screen corruption | Low | Proper raw mode exit sequence |
| Performance | Low | Async tasks, buffer sizes tuned |

---

## Dependencies

```toml
[dependencies]
crossterm = "0.28"
```

---

## Success Criteria

- [ ] Ctrl+C cancels remote command, NOT client
- [ ] `vim` works correctly (insert mode, visual mode, save/quit)
- [ ] `htop` displays correctly
- [ ] ANSI colors preserved
- [ ] `/exit` cleanly disconnects
- [ ] Terminal state restored on exit

---

## Next Steps

1. **Create implementation plan** using `/plan` command
2. **Start with Phase 1** (core raw mode)
3. **Test incrementally** (pwd → vim → htop)

---

**Unresolved Questions**:
- Should we add a status bar overlay in future? (Deferred to Phase 08)
- Should we support local commands (e.g., `/disconnect`)? (Deferred)

**Recommendation**: Start with raw mode passthrough. It's the simplest, most robust solution that perfectly matches your "SSH-like" requirement. Custom TUI overlays can be added later if needed (YAGNI principle).
