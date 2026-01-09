# Phase 03: Server Cleanup

**Priority**: P1 (High)
**Effort**: 3h
**Status**: ✅ Done (2026-01-09)

## Overview

Remove duplicate PTY spawn logic, clean up debug code, fix misleading comments in server.

## Context Links

- [Scout: Server Analysis](../scout/scout-server-report.md)

## Requirements

1. Extract duplicate spawn logic to shared function
2. Remove Vietnamese comments
3. Fix misleading "300ms delay" comment
4. Reduce debug log noise
5. Standardize terminology

## Implementation Steps

### Step 1: Extract Shared Spawn Function

**Before**: 137 lines of duplicate code (lines 262-401)

**After**: Single helper function

```rust
impl QuicServer {
    /// Spawn session with terminal configuration
    async fn spawn_session_with_config(
        session_mgr: Arc<SessionManager>,
        pending_resize: Option<(u16, u16)>,
        pty_task: &mut Option<tokio::task::JoinHandle<()>>,
        session_id: &mut Option<u64>,
        send_shared: Arc<Mutex<quinn::SendStream>>,
        initial_data: &[u8],
    ) -> Result<()> {
        let mut config = comacode_core::terminal::TerminalConfig::default();

        // Apply resize if available
        if let Some((rows, cols)) = pending_resize {
            config.rows = rows;
            config.cols = cols;
            config.env.push(("COLUMNS".to_string(), cols.to_string()));
            config.env.push(("LINES".to_string(), rows.to_string()));
            config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
        }

        // Create session
        match session_mgr.create_session(config).await {
            Ok(id) => {
                *session_id = Some(id);
                tracing::info!("Session {} created", id);

                // Resize to sync PTY driver
                if let Some((rows, cols)) = pending_resize {
                    let _ = session_mgr.resize_session(id, rows, cols).await;
                }

                // Spawn PTY pump task
                if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                    let send_clone = send_shared.clone();
                    *pty_task = Some(tokio::spawn(async move {
                        let mut send_lock = send_clone.lock().await;
                        if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
                            tracing::error!("PTY pump error: {}", e);
                        }
                    }));
                }

                // Write initial data if any
                if !initial_data.is_empty() {
                    let _ = session_mgr.write_to_session(id, initial_data).await;
                }

                Ok(())
            }
            Err(e) => {
                tracing::error!("Failed to create session: {}", e);
                Err(e)
            }
        }
    }
}
```

### Step 2: Update Message Handlers

**Before**: Duplicate code in Input and Command handlers

**After**:
```rust
NetworkMessage::Input { data } => {
    if !authenticated {
        break;
    }

    if let Some(id) = session_id {
        session_mgr.write_to_session(id, &data).await?;
    } else {
        Self::spawn_session_with_config(
            session_mgr, pending_resize, &mut pty_task,
            &mut session_id, send_shared, &data,
        ).await?;
    }
}

NetworkMessage::Command(cmd) => {
    // Same pattern - call shared function
    if let Some(id) = session_id {
        session_mgr.write_to_session(id, cmd.text.as_bytes()).await?;
    } else {
        Self::spawn_session_with_config(
            session_mgr, pending_resize, &mut pty_task,
            &mut session_id, send_shared, cmd.text.as_bytes(),
        ).await?;
    }
}
```

### Step 3: Remove Vietnamese Comments

**Locations**: Lines 276-293, 354-366

**Before:**
```rust
// ===== PINCER MOVEMENT (GỌNG KÌM) =====
// 1. Env vars (0ms) → Zsh reads COLUMNS/LINES FIRST
```

**After:**
```rust
// Configure terminal with COLUMNS/LINES env vars
// Zsh reads these before querying PTY driver
```

### Step 4: Fix Misleading Comments

**Location**: Lines 302-308

**Before:**
```rust
// Immediate resize: Sync PTY Driver with Env Vars (0ms)
// Zsh reads COLUMNS=147 from env, but PTY Driver ioctl still says 80
```

**After:**
```rust
// Resize PTY to match terminal size
// This syncs the PTY driver with env vars
```

### Step 5: Reduce Debug Log Noise

**Locations**: Lines 216, 294, 330, 366, 417

**Before:**
```rust
tracing::debug!("Received message: {:?}", std::mem::discriminant(&msg));
```

**After:**
```rust
tracing::trace!("Message: {:?}", std::mem::discriminant(&msg));
```

## Related Code Files

### Modify
- `crates/hostagent/src/quic_server.rs`

## Todo List

- [x] Extract spawn_session_with_config() helper
- [x] Update Input handler to use helper
- [x] Update Command handler to use helper
- [x] Remove Vietnamese comments
- [x] Fix misleading comments
- [x] Change debug! to trace! for discriminant
- [x] Test both spawn paths work identically

## Success Criteria

1. No duplicate code between Input and Command handlers
2. All Vietnamese comments removed
3. Comments accurately describe code behavior
4. Both spawn paths produce identical results

## Risk Assessment

**Risk**: Extracting function may introduce bugs
**Mitigation**: Test both paths thoroughly, keep logic identical

**Risk**: Regression in spawn behavior
**Mitigation**: Compare behavior before/after, add logging

---

## Completion Summary (2026-01-09)

**Delivered**:
- ✅ Extracted `spawn_session_with_config()` helper function
- ✅ Updated Input and Command handlers to use shared helper
- ✅ Changed `debug!` to `trace!` for discriminant logging
- ✅ Eliminated 137 lines of duplicate code

**Code Review**: 0 critical issues found

**Files Modified**:
- `crates/hostagent/src/quic_server.rs`

**Next Steps**: Proceed to Phase 04 (PTY Pump Refactor)
