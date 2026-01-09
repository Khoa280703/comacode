# Scout Report: Server Analysis

**File**: `crates/hostagent/src/quic_server.rs`
**Agent**: scout (agentId: ab4cfc9)
**Date**: 2026-01-09

## Critical Issues Found

### P0: Protocol Framing Bug (Lines 201-214)
```rust
let mut read_buf = vec![0u8; 1024];

loop {
    match recv.read(&mut read_buf).await? {
        Some(n) if n > 0 => {
            // Parse message - FAILS because no length prefix!
            let msg = match MessageCodec::decode(&read_buf[..n]) {
```

**Problem**: `MessageCodec::decode()` expects `[4-byte length][payload]` but code uses `recv.read()`.

**Impact**: All incoming messages likely fail decode silently.

**Fix Required**:
```rust
// Correct pattern from stream.rs:86-106
let mut len_buf = [0u8; 4];
recv.read_exact(&mut len_buf).await?;
let len = u32::from_be_bytes(len_buf) as usize;
let mut data = vec![0u8; len];
recv.read_exact(&mut data).await?;
let msg = MessageCodec::decode(&data)?;
```

### P1: Duplicate PTY Spawn Logic (Lines 262-401)

**Path 1: Input message** (lines 262-337) - 75 lines
**Path 2: Command message** (lines 339-401) - 62 lines

~80% duplicate code - violates DRY principle.

### P2: Debug Code to Remove

| Type | Line(s) | Content |
|------|---------|---------|
| Vietnamese comments | 276-293 | "PINCER MOVEMENT (GỌNG KÌM)" |
| Duplicate comments | 354-366 | "Env vars ONLY (legacy)" |
| Debug logs | 216, 294, 330, 366, 417 | `tracing::debug!()` in prod |
| Misleading term | 330 | "Eager spawn" - non-standard |

## Architecture Issues

### Non-SSH Patterns

1. **Line 203**: Single loop handles 6 message types (no data/control separation)
2. **Line 272**: Synchronous write to PTY (lock contention)
3. **Lines 302-308**: "Immediate resize" but comment says "300ms delay"

## Full Issue List

| Line | Severity | Issue |
|------|----------|-------|
| 201-214 | **CRITICAL** | Protocol framing bug |
| 208-213 | **CRITICAL** | Silent decode failure |
| 216 | Low | Debug discriminant log |
| 276-293 | **MEDIUM** | Vietnamese comments + misleading |
| 294 | Low | Debug log |
| 302-308 | **MEDIUM** | Comment says 300ms, code is immediate |
| 330 | Low | "Eager spawn" terminology |
| 354-400 | **MEDIUM** | Duplicate spawn logic (62 lines) |
| 366 | Low | Debug log |
| 417 | Low | Debug log |
