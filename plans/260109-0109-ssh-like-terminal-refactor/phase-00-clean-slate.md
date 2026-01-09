# Phase 00: Clean Slate - Revert All Temp Fixes

**Priority**: P0 (Critical)
**Effort**: 1h
**Status**: Pending

## Overview

Revert ALL temporary fixes from debugging session (11 attempts). Start with cleanest SSH-like codebase.

**Rationale**: After 11+ failed attempts, code has accumulated workarounds that mask the real issue. Protocol framing bug is the root cause - fix that first on clean code.

## Context Links

- [Analysis of All Failed Attempts](../../reports/analysis-260109-0030-zsh-prompt-timing-unresolved.md)

## Temp Fixes to Revert

### 1. Ping to Force QUIC Flush (main.rs:147-149)
```rust
// REMOVE THIS:
send.write_all(&MessageCodec::encode(&NetworkMessage::ping())?).await?;
```

### 2. Double-Tap Resize with 300ms Delay (quic_server.rs:296-309)
```rust
// REMOVE THIS:
tokio::spawn(async move {
    tokio::time::sleep(Duration::from_millis(300)).await;
    mgr_clone.resize_session(id, rows, cols).await;
});
```

### 3. "Pincer Movement" Logic (quic_server.rs:276-316)
- Remove Vietnamese comments "PINCER MOVEMENT (GỌNG KÌM)"
- Simplify resize logic (env vars OK, but remove misleading "delayed" comments)
- Keep only immediate resize after spawn

### 4. Banner Modifications (main.rs:117-128)
- Already reverted to `\r\n\r\n` ending
- Remove `\r\x1b[K` if any remains

### 5. Eager Spawn "Trigger" Comments
- Keep eager spawn (good for SSH-like)
- Remove confusing "trigger" terminology
- Simplify comments

### 6. COLUMNS/LINES Env Vars
- Keep these (they are actually correct for SSH-like behavior)
- But remove "Pincer Movement" context

### 7. PROMPT_EOL_MARK Env Var
- Keep this (hides `%` marker)
- Remove misleading comments

## Keep (These Are Correct)

✅ **Resize before spawn** - Correct SSH pattern
✅ **Env vars (COLUMNS, LINES)** - Standard practice
✅ **Immediate resize** - Syncs PTY driver
✅ **Eager spawn** - Like SSH

## Remove (These Are Workarounds)

❌ **Ping for QUIC flush** - Protocol framing fix will handle this
❌ **300ms delayed resize** - Timing hack
❌ **Vietnamese comments** - "GỌNG KÌM", etc.
❌ **Misleading "delayed" terminology** - Code is immediate
❌ **"Eager spawn trigger"** - Just "spawn session"

## Implementation Steps

### Step 1: Clean Client (main.rs)

Remove ping workaround:
```rust
// BEFORE (lines 147-149):
// Optional: Gửi Ping để force flush QUIC stream (đảm bảo trigger đi ngay)
send.write_all(&MessageCodec::encode(&NetworkMessage::ping())?).await?;

// AFTER:
// (Remove these lines entirely)
```

### Step 2: Clean Server Spawn Logic (quic_server.rs)

Simplify Input message handler:
```rust
// BEFORE (lines 276-336): 60 lines with "Pincer Movement" comments

// AFTER: Simplify to ~30 lines
NetworkMessage::Input { data } => {
    if !authenticated { break; }

    if let Some(id) = session_id {
        // Write to existing session
        session_mgr.write_to_session(id, &data).await.ok();
    } else {
        // Spawn new session with terminal configuration
        let mut config = comacode_core::terminal::TerminalConfig::default();

        // Apply terminal size from earlier Resize message
        if let Some((rows, cols)) = pending_resize.take() {
            config.rows = rows;
            config.cols = cols;
            config.env.push(("COLUMNS".to_string(), cols.to_string()));
            config.env.push(("LINES".to_string(), rows.to_string()));
            config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
        }

        match session_mgr.create_session(config).await {
            Ok(id) => {
                session_id = Some(id);

                // Resize PTY to match terminal
                if let Some((rows, cols)) = pending_resize {
                    session_mgr.resize_session(id, rows, cols).await.ok();
                }

                // Start PTY output pump
                if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                    let send_clone = send_shared.clone();
                    pty_task = Some(tokio::spawn(async move {
                        let mut send_lock = send_clone.lock().await;
                        pump_pty_to_quic(pty_reader, &mut *send_lock).await.ok();
                    }));
                }

                // Write initial data (if any)
                if !data.is_empty() {
                    session_mgr.write_to_session(id, &data).await.ok();
                }
            }
            Err(e) => {
                tracing::error!("Failed to create session: {}", e);
            }
        }
    }
}
```

### Step 3: Clean Command Handler (quic_server.rs)

Same simplification as Input handler - remove duplicate code, use shared pattern.

### Step 4: Verify Clean State

```bash
# Check no remaining temp fixes:
grep -n "300ms\|Pincer\|GỌNG KÌM\|trigger" crates/hostagent/src/quic_server.rs
grep -n "ping()" crates/cli_client/src/main.rs

# Should return nothing (except possibly this comment)
```

## Related Code Files

### Modify
- `crates/cli_client/src/main.rs` - Remove ping workaround
- `crates/hostagent/src/quic_server.rs` - Simplify spawn logic

## Todo List

- [ ] Remove ping workaround from client (main.rs:147-149)
- [ ] Remove 300ms delayed resize (quic_server.rs:296-309)
- [ ] Remove "Pincer Movement" Vietnamese comments
- [ ] Simplify Input message handler
- [ ] Simplify Command message handler
- [ ] Verify no temp fixes remain
- [ ] Test basic connection still works

## Success Criteria

1. No "ping" calls in main loop
2. No "300ms" delays in server
3. No Vietnamese comments
4. Spawn logic < 40 lines per handler
5. Terminal size still applied correctly

## Risk Assessment

**Risk**: Reverting may break something that was "sort of working"
**Mitigation**: Protocol framing fix (Phase 01) will address actual root cause

**Risk**: Losing working configuration
**Mitigation**: Git history allows recovery if needed
