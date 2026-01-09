---
title: "Fix CLI Client + Regenerate FRB Bindings"
description: "Make cli_client interactive terminal + fix mobile_bridge compilation errors"
status: pending
priority: P1
effort: 3h
issue: 0
branch: main
tags: [bugfix, cli, flutter-rust-bridge, terminal]
created: 2026-01-08
---

# Fix CLI Client + Regenerate FRB Bindings

## Overview

**Problem 1**: `cli_client` only does connection test (ping/pong), then disconnects. NO interactive terminal mode.

**Problem 2**: `mobile_bridge` has 95 compilation errors due to wrong imports in `frb_generated.rs`.

**Impact**: Cannot test Phase 05.1 (Terminal Streaming) end-to-end. Cannot rebuild Flutter app.

---

## Root Cause Analysis

### Problem 1: CLI Client Stub

**File**: `crates/cli_client/src/main.rs:195-199`

```rust
// Send Close to gracefully end connection
let close = NetworkMessage::Close;
send.write_all(&MessageCodec::encode(&close)?).await?;
println!("📡 Closing connection");
```

**Issue**: Client sends `Close` immediately after ping/pong test. Never enters terminal mode.

**Missing**:
1. Stdin → Command send loop
2. Terminal event receive loop
3. PTY creation trigger (first command)

### Problem 2: FRB Generated Wrong Imports

**File**: `crates/mobile_bridge/src/frb_generated.rs:31, 1780, 1847`

```rust
// WRONG (generated this way):
use mobile_bridge::api::*;

// Should be:
use crate::api::*;
```

**Root Cause**: FRB generated with wrong crate context.

**Fix**: Regenerate `frb_generated.rs` with proper config.

---

## Solution Design

### Part 1: Fix CLI Client (1.5h)

**Approach**: Replace connection test with interactive terminal loop.

**⚠️ Technical Considerations**:
- **Trim trailing newlines**: PTY may auto-append `\n`, so trim before sending
- **Raw byte output**: Use `write_all()` not `print!()` for ANSI/binary data
- **Line mode MVP**: Keep line-by-line for MVP (vim/top needs raw mode → future)

```rust
// AFTER HANDSHAKE (replace line 149-199):

// Spawn event receiver task (background)
let recv_clone = recv.clone();
let event_task = tokio::spawn(async move {
    let mut buf = vec![0u8; 8192];
    loop {
        match recv_clone.read(&mut buf).await {
            Ok(Some(n)) if n > 0 => {
                if let Ok(msg) = MessageCodec::decode(&buf[..n]) {
                    match msg {
                        NetworkMessage::Event(event) => {
                            // Write RAW bytes (ANSI colors, binary safe)
                            let _ = std::io::stdout().write_all(&event.data);
                            let _ = std::io::stdout().flush();
                        }
                        NetworkMessage::Close => break,
                        _ => {}
                    }
                }
            }
            Ok(None) => break,
            Err(_) => break,
        }
    }
});

// Enter interactive mode
println!("🖥️  Terminal ready. Type 'exit' to quit.");

let stdin = tokio::io::stdin();
let reader = stdin;
let mut line = String::new();

loop {
    line.clear();

    // Read from stdin (blocking, line mode)
    reader.read_line(&mut line).await?;

    let cmd_text = line.trim_end();
    if cmd_text == "exit" {
        break;
    }

    // Send command (trimmed - PTY will handle newline)
    let cmd = NetworkMessage::Command(TerminalCommand {
        text: cmd_text.to_string(),
    });
    send.write_all(&MessageCodec::encode(&cmd)?).await?;
}

// Cleanup
event_task.abort();
let _ = send.finish();
```

**Tasks**:
1. Remove ping/pong test code (lines 149-193)
2. Add event receiver background task with `write_all()`
3. Add stdin read loop with `trim_end()`
4. Add "exit" command handling
5. Test with `ls`, `pwd`, `echo test`

### Part 2: Regenerate FRB (0.5h)

**Approach**: Create `frb_config.yaml` and regenerate.

```yaml
# crates/mobile_bridge/frb_config.yaml
rust:
  input: src/api.rs
  crate_name: mobile_bridge
  crate_type: lib

dart:
  output: ../mobile/lib/bridge/
  structure: inline
```

**Regenerate**:
```bash
cd crates/mobile_bridge
flutter_rust_bridge_codegen --rust-input src/api.rs --dart-output ../../mobile/lib/bridge/
```

**Tasks**:
1. Create `frb_config.yaml`
2. Backup existing `frb_generated.rs`
3. Run regeneration command
4. Verify `cargo build -p mobile_bridge` succeeds

---

## Task Breakdown

### Phase 1: CLI Client Interactive Mode (1-1.5h)

| Task | File | Change |
|------|------|--------|
| 1.1 | `cli_client/src/main.rs` | Remove ping/pong test (lines 149-193) |
| 1.2 | `cli_client/src/main.rs` | Add event receiver background task |
| 1.3 | `cli_client/src/main.rs` | Add stdin read loop |
| 1.4 | `cli_client/src/main.rs` | Add exit command handling |
| 1.5 | `cli_client/` | Test `ls`, `pwd`, `echo` commands |

### Phase 2: FRB Regeneration (0.5h)

| Task | File | Change |
|------|------|--------|
| 2.1 | `mobile_bridge/frb_config.yaml` | Create config |
| 2.2 | `mobile_bridge/src/frb_generated.rs` | Backup old file |
| 2.3 | `mobile_bridge/` | Run flutter_rust_bridge_codegen |
| 2.4 | `mobile_bridge/` | Verify cargo build succeeds |

---

## Acceptance Criteria

### CLI Client
- [ ] Connects successfully
- [ ] Shows "Terminal ready" message
- [ ] Can type commands and see output
- [ ] `ls` shows directory listing
- [ ] `pwd` shows current directory
- [ ] `exit` disconnects cleanly
- [ ] Terminal output appears in real-time

### FRB Fix
- [ ] `cargo build -p mobile_bridge` succeeds
- [ ] `cargo test --workspace` passes
- [ ] Flutter app can be rebuilt
- [ ] No `use mobile_bridge::` imports in generated code

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stdin blocking issues | Medium | Use tokio::io::async stdin |
| Event receiver race | Low | Use cloned recv handle |
| FRB regenerate breaks API | Medium | Backup before regenerate |
| Terminal ANSI codes | Low | Direct print (no parsing) |

---

## Dependencies

- None (both tasks independent)

**Technical Constraints**:
- Line-mode only for MVP (vim/top needs raw mode → Phase 08)
- No local echo (server echoes back)
- No signal handling (Ctrl+C sent as command, not signal)

---

## Next Steps After This Plan

1. **Test Phase 05.1**: Run `ls` via cli_client, verify output streams back
2. **Update Phase Status**: Mark 05.1 as "100% Complete" in plan.md
3. **Flutter Test**: Test mobile app if FRB fix works
4. **Phase 07**: Start mDNS Discovery

---

## Unresolved Questions

1. ~~Should we add `--raw` mode to cli_client?~~ → **ANSWERED**: Line-mode MVP first, raw mode (vim/top) → Phase 08
2. Should FRB generation be automated in CI/CD?
3. Should `trim_end()` remove `\r\n` or just `\n`? (Windows vs Unix)

---

**Created**: 2026-01-08
**Estimate**: 3h total (1.5h CLI + 0.5h FRB + 1h testing/buffer)
