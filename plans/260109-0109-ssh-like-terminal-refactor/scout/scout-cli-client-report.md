# Scout Report: CLI Client Analysis

**File**: `crates/cli_client/src/main.rs`
**Agent**: scout (agentId: a3cc028)
**Date**: 2026-01-09

## Critical Issues Found

### P0: Protocol Framing Bug (Lines 110-114, 194-213)
```rust
// BROKEN: Using read() instead of read_exact()
let n = match recv.read(&mut buf).await? {
    Some(n) => n,
    None => return Err(anyhow::anyhow!("Closed")),
};
let _ = MessageCodec::decode(&buf[..n])?;
```

**Problem**: Protocol requires `[4-byte length][payload]` but code uses `read()` which may return partial data.

**Fix Required**: Use `read_exact()` pattern from `stream.rs:86-106`.

### P1: Raw Mode Silent Failure (Lines 133-136)
```rust
let _guard = match raw_mode::RawModeGuard::enable() {
    Ok(guard) => Some(guard),
    Err(_) => None,  // Silent failure!
};
```

**Problem**: Continues without raw mode if TTY not available. No user warning.

### P2: Debug Code to Remove

| Type | Line(s) | Content |
|------|---------|---------|
| Vietnamese comments | 1-2, 21, 87, 132, 138, 145, 150, 154, 170 | "// Gửi Resize -> ..." |
| Emoji output | 88, 89, 115, 122-123 | 🔧 📡 ✅ 🚀 |
| Misleading comment | 197 | "QUIC should give us complete messages" |

### P3: Non-SSH Patterns

1. **Line 167-169**: `/exit` as string check instead of escape sequence (`~.`)
2. **Line 223**: `abort()` instead of graceful shutdown
3. **Line 215-220**: Sleep-based EOF check instead of channel close notification

## Code Quality Issues

- **Line 92-94**: Forces `--insecure` flag (temporary dev code?)
- **Line 99**: `unwrap()` in setup code
- **Line 118, 128, 202, 226, 228**: Silently ignored write results
- **Line 161**: Magic buffer size 1024 (vs 8192 for recv)

## Full Issue List with Line Numbers

| Line | Severity | Issue |
|------|----------|-------|
| 1-2 | Low | Vietnamese comment |
| 21 | Low | Vietnamese placeholder |
| 88 | Low | Emoji 🔧 |
| 89 | Low | Emoji 📡 |
| 92-94 | Medium | Forces --insecure |
| 99 | Low | unwrap() |
| 110-114 | **HIGH** | **read() not read_exact()** |
| 115 | Low | Emoji ✅ |
| 118-129 | Medium | Escape sequences + emoji |
| 132 | Low | Vietnamese comment |
| 133-136 | **MEDIUM** | Silent raw mode failure |
| 138-153 | Low | Vietnamese comments (5) |
| 158-183 | **MEDIUM** | Blocking I/O in async |
| 167-169 | Medium | String /exit vs escape |
| 170 | Low | Vietnamese comment |
| 194-213 | **HIGH** | **read() not accumulation** |
| 197 | Medium | Misleading comment |
| 215-220 | Medium | Sleep-based EOF |
| 223 | Medium | abort() usage |
| 226 | **MEDIUM** | Hardcoded terminal reset |
