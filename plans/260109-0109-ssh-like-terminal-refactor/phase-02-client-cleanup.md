# Phase 02: Client Cleanup

**Priority**: P1 (High)
**Effort**: 2h
**Status**: Pending

## Overview

Remove all debug code, Vietnamese comments, emoji output from CLI client. Improve SSH-like patterns.

## Context Links

- [Scout: Client Analysis](../scout/scout-cli-client-report.md)

## Requirements

1. Remove all Vietnamese comments
2. Remove emoji output (🔧📡✅🚀)
3. Fix misleading comments
4. Improve raw mode handling
5. Use SSH-like escape sequences
6. **[NEW]** Add SIGWINCH handling for dynamic terminal resize

## Implementation Steps

### Step 1: Remove Vietnamese Comments

**Locations**: Lines 1-2, 21, 87, 132, 138, 145, 150, 154, 170

**Before:**
```rust
//! Minimal QUIC client để test Comacode backend
// Gửi Resize -> Gửi Input Rỗng -> Gửi Ping (Flush)
```

**After:**
```rust
//! QUIC client for Comacode remote terminal
// Send Resize -> Empty Input -> Ping (force flush)
```

### Step 2: Remove Emoji Output

**Locations**: Lines 88, 89, 115, 122-123

**Before:**
```rust
println!("🔧 Comacode CLI Client");
println!("📡 Connecting to {}...", args.connect);
println!("✅ Connected & Authenticated");
```

**After:**
```rust
println!("Comacode CLI Client v{}", env!("CARGO_PKG_VERSION"));
println!("Connecting to {}...", args.connect);
println!("Authenticated");
```

### Step 3: Fix Raw Mode Handling (Line 133-136)

**Before:**
```rust
let _guard = match raw_mode::RawModeGuard::enable() {
    Ok(guard) => Some(guard),
    Err(_) => None,  // Silent failure!
};
```

**After:**
```rust
let _guard = match raw_mode::RawModeGuard::enable() {
    Ok(guard) => Some(guard),
    Err(e) => {
        eprintln!("Warning: Raw mode not available: {}. Input may be slow.", e);
        None
    }
};
```

### Step 4: Fix /exit Command (Line 167-169)

**Before:**
```rust
if String::from_utf8_lossy(&buf[..n]).trim() == "/exit" {
    break;
}
```

**After:**
```rust
// SSH-like: Ctrl+D sends EOF, use that for exit
// /exit still works as convenience
let input = String::from_utf8_lossy(&buf[..n]);
if input.trim() == "/exit" || n == 0 {  // Empty line also exits
    break;
}
```

### Step 5: Fix Misleading Comment (Line 197)

**Before:**
```rust
// Direct decode - QUIC should give us complete messages
```

**After:**
```rust
// Decode length-prefixed message from buffer
```

### Step 6: Fix Terminal Reset (Line 226)

**Before:**
```rust
let _ = std::io::stdout().write_all(b"\x1b]0;\x07\x1b[!p\x1bc\r\nConnection closed.\r\n");
```

**After:**
```rust
// Reset terminal using crossterm
let _ = terminal::disable_raw_mode();
println!("\r\nConnection closed.");
```

### Step 7: **[NEW]** Add SIGWINCH Handling for Dynamic Resize

**Problem**: If user resizes terminal during session (vim, htop), display breaks.

**Solution**: Listen for SIGWINCH and send Resize message to server.

**Add to main.rs after eager spawn:**
```rust
use tokio::signal::unix::{signal, SignalKind};

// Clone send for SIGWINCH task
let send_resize = send.clone();
let resize_tx = stdin_tx.clone();

tokio::spawn(async move {
    // Create SIGWINCH signal stream
    match signal(SignalKind::window_change()) {
        Ok(mut stream) => {
            loop {
                stream.recv().await;
                if let Ok((cols, rows)) = size() {
                    let resize_msg = NetworkMessage::Resize { rows, cols };
                    if let Ok(encoded) = MessageCodec::encode(&resize_msg) {
                        let _ = resize_tx.send(encoded).await;
                    }
                }
            }
        }
        Err(_) => {
            tracing::debug!("SIGWINCH not available on this platform");
        }
    }
});
```

**Note**: Requires `tokio::signal` feature (already in tokio).

## Related Code Files

### Modify
- `crates/cli_client/src/main.rs`

### Reference
- `crates/cli_client/src/raw_mode.rs` - Use crossterm API

## Todo List

- [ ] Remove Vietnamese comments (9 locations)
- [ ] Remove emoji output (4 locations)
- [ ] Fix raw mode warning message
- [ ] Fix /exit handling
- [ ] Fix misleading comment
- [ ] Fix terminal reset sequence
- [ ] **[NEW]** Add SIGWINCH handling for dynamic resize
- [ ] Test cleanup works correctly

## Success Criteria

1. No Vietnamese comments remain
2. No emoji in output
3. Raw mode failure warns user
4. Terminal reset compatible with most terminals
5. **[NEW]** Terminal resize works during session (vim, htop resize correctly)

## Risk Assessment

**Risk**: Low - pure cleanup, no logic changes

**Risk**: Terminal reset may not work on all terminals
**Mitigation**: Use crossterm cross-platform API
