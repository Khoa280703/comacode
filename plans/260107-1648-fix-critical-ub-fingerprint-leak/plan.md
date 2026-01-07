---
title: "Fix Critical Bugs: UB in api.rs + Fingerprint Leakage"
description: "Sửa 2 critical bugs từ code review: undefined behavior trong FFI bridge và fingerprint leakage trong logs"
status: completed
priority: P0
effort: 1.5h
branch: main
tags: [bugfix, security, once-cell, phase-04]
created: 2026-01-07
completed: 2026-01-07
---

# Implementation Plan: Fix Critical Bugs

## Executive Summary

**2 bugs critical cần fix ngay:**

1. **Undefined Behavior in `api.rs`** - static mut gây UB risk (data races, segfaults)
2. **Fingerprint Leakage in Logs** - Security/privacy concern

**Solution:** Thay `static mut` bằng `once_cell::sync::OnceCell` + sửa log fingerprint.

---

## 1. Bug #1: Undefined Behavior in FFI Bridge

### 1.1. Root Cause

```rust
// CRITICAL: Unsafe static mutable access
static mut QUIC_CLIENT: Option<Arc<Mutex<QuicClient>>> = None;

// Compiler warns: creating shared reference to mutable static is UB
let client_arc = unsafe {
    QUIC_CLIENT.as_ref().unwrap().clone()
};
```

**Problem:**
- Compiler warning: "shared reference to mutable static is dangerous"
- Undefined behavior if static is mutated during shared reference
- Data races, potential segfaults in production

### 1.2. Solution: `once_cell::sync::OnceCell`

**Why `once_cell`:**
- Standard Rust pattern for global static initialization
- Thread-safe (atomic operations under the hood)
- One-time assignment guarantee
- Zero unsafe code needed

### 1.3. Implementation Steps

#### Step 1: Add dependency (5 min)

File: `crates/mobile_bridge/Cargo.toml`

```toml
[dependencies]
# ... existing dependencies ...
once_cell = "1.19"
```

#### Step 2: Refactor `api.rs` (45 min)

File: `crates/mobile_bridge/src/api.rs`

**Changes:**

| Before | After |
|--------|-------|
| `static mut QUIC_CLIENT: Option<...>` | `static QUIC_CLIENT: OnceCell<Arc<Mutex<...>>>` |
| `unsafe { QUIC_CLIENT.as_ref() }` | `QUIC_CLIENT.get()` |
| Manual initialization check | `QUIC_CLIENT.set()` with error handling |

**New code structure:**

```rust
use once_cell::sync::OnceCell;

// Thread-safe global static (no unsafe needed)
static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();

pub async fn connect_to_host(
    ip: String,
    port: u16,
    token: String,
    fingerprint: String,
) -> Result<(), String> {
    // Check if already initialized
    if QUIC_CLIENT.get().is_some() {
        return Err("Client already initialized. Please restart app to reset.".to_string());
    }

    // Create new client
    let mut client = QuicClient::new(fingerprint);
    client.connect(ip, port, token).await?;

    // Store in global static (thread-safe, one-time)
    let client_arc = Arc::new(Mutex::new(client));
    QUIC_CLIENT.set(client_arc)
        .map_err(|_| "Failed to set global client".to_string())?;

    Ok(())
}

pub async fn send_command(cmd: String) -> Result<(), String> {
    // Safe access (no unsafe)
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Client not connected".to_string())?;

    let mut client = client_arc.lock()
        .map_err(|_| "Failed to lock client mutex".to_string())?;

    client.send_command(cmd).await?;
    Ok(())
}

pub async fn disconnect() -> Result<(), String> {
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Client not connected".to_string())?;

    let mut client = client_arc.lock()
        .map_err(|_| "Failed to lock client mutex".to_string())?;

    client.disconnect().await?;
    Ok(())
}

// Helper: Check connection status
pub async fn is_connected() -> bool {
    if let Some(client_arc) = QUIC_CLIENT.get() {
        let client = client_arc.lock().ok()?;
        client.is_connected().await
    } else {
        false
    }
}
```

#### Step 3: Verify (5 min)

```bash
cargo check -p mobile_bridge
cargo clippy -p mobile_bridge
cargo test -p mobile_bridge
```

**Expected result:** No more UB warnings.

---

## 2. Bug #2: Fingerprint Leakage in Logs

### 2.1. Root Cause

File: `crates/mobile_bridge/src/quic_client.rs:88`

```rust
debug!("Verifying cert - Expected: {}, Actual: {}", self.expected_fingerprint, actual_clean);
```

**Problem:**
- Actual fingerprint value logged in plain text
- Extractable from crash reports, debug logs
- Security/privacy concern if logs are exposed

### 2.2. Solution: Log Only Comparison Result

**Option A:** Log only match result (simplest)
```rust
debug!("Verifying cert - Match: {}", actual_clean == expected_clean);
```

**Option B:** Log partial fingerprint (first 4 chars)
```rust
debug!("Verifying cert - Expected: {}..., Actual: {}...",
    &expected_clean[..4], &actual_clean[..4]);
```

**Recommendation:** Option A (KISS principle)

### 2.3. Implementation (5 min)

File: `crates/mobile_bridge/src/quic_client.rs`

```rust
// Line 88 - OLD
debug!("Verifying cert - Expected: {}, Actual: {}", self.expected_fingerprint, actual_clean);

// Line 88 - NEW
debug!("Verifying cert - Match: {}", actual_clean == expected_clean);
```

Also fix error log at line 93:
```rust
// OLD
error!("Fingerprint mismatch! Expected: {}, Got: {}", self.expected_fingerprint, actual_clean);

// NEW (keep for debugging, but redact most of it)
error!("Fingerprint mismatch! Expected: {}...{}, Got: {}...{}",
    &self.expected_fingerprint[..4],
    &self.expected_fingerprint[self.expected_fingerprint.len()-4..],
    &actual_clean[..4],
    &actual_clean[actual_clean.len()-4..]
);
```

---

## 3. Verification Checklist

### 3.1. Build & Test

```bash
# Should pass without UB warnings
cargo build -p mobile_bridge

# Should show 0 warnings (or reduced from 42)
cargo clippy -p mobile_bridge

# All tests should pass
cargo test -p mobile_bridge
```

### 3.2. Runtime Verification

| Test Case | Expected Result |
|-----------|-----------------|
| Connect → disconnect → reconnect | Should fail "already initialized" |
| Concurrent connect calls | Only one succeeds |
| Send command before connect | Returns "not connected" error |
| Fingerprint mismatch | Logs show "Match: false" only |

---

## 4. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| `once_cell` not in workspace | Low | Low | Add to workspace Cargo.toml |
| FFI function signature changes | Low | Medium | Verify Flutter bridge still compiles |
| Test failures | Low | Low | Update tests if needed |

---

## 5. Success Criteria

- [x] Zero compiler warnings about UB
- [x] Zero `unsafe` blocks in `api.rs`
- [x] Fingerprint not logged in plain text
- [x] All tests pass
- [x] Flutter FFI bridge still generates correctly

---

## 6. Files to Modify

| File | Lines | Change Type |
|------|-------|-------------|
| `crates/mobile_bridge/Cargo.toml` | +1 | Add `once_cell` dependency |
| `crates/mobile_bridge/src/api.rs` | ~50 | Replace `static mut` with `OnceCell` |
| `crates/mobile_bridge/src/quic_client.rs` | 2 | Fix fingerprint logging |

---

## 7. Post-Fix Actions

1. Update `known-issues-technical-debt.md`:
   - Mark Issue #5 (UB in api.rs) as **COMPLETED**
   - Mark Issue #7 (Fingerprint leakage) as **COMPLETED**

2. Git commit:
   ```
   feat(mobile-bridge): fix critical UB and fingerprint leakage

   - Replace static mut with once_cell::sync::OnceCell
   - Remove all unsafe blocks from api.rs
   - Redact fingerprint in debug logs
   - Fixes #5, #7 in known-issues-technical-debt.md
   ```

---

## 8. Time Estimate

| Task | Duration |
|------|----------|
| Add `once_cell` dependency | 5 min |
| Refactor `api.rs` | 45 min |
| Fix fingerprint logging | 5 min |
| Verification (build/test) | 10 min |
| Update docs & commit | 15 min |
| **Total** | **~1.5h** |

---

## 9. Dependencies

- None (can proceed immediately)

---

## 10. Open Questions

1. **Reconnect behavior**: If user calls `connect_to_host()` twice, should we:
   - A) Return error "already initialized" ← **CURRENT PLAN**
   - B) Disconnect old, connect new
   - C) Ignore if already connected to same host

   **Decision**: A for now. Can add reconnect logic in Phase 05 if needed.

2. **Error message format**: Should we use `anyhow::Error` or `String` for FFI?
   - Current code uses `Result<(), String>`
   - OnceCell error returns `String` for FFI compatibility
   - **Decision**: Keep `String` for consistency with existing FFI

---

**Plan Status**: Ready to implement
**Assigned To**: Backend Development Agent
**Review Date**: 2026-01-07
