# Scout Report: Transport & PTY Analysis

**Files**: `stream.rs`, `pty.rs`
**Agent**: scout (agentId: a0dd782)
**Date**: 2026-01-09

## Critical Issues Found

### P0: PTY Output Pump Bug (stream.rs Line 40)
```rust
let n = pty.read(&mut buf).await?;  // Partial reads!

// Then wraps EACH read as separate message:
let msg = NetworkMessage::Event(TerminalEvent::Output {
    data: buf[..n].to_vec()  // Each buffer = 1 message!
});
```

**Problem**: Terminal output is a byte stream, but code wraps each `read()` as separate `NetworkMessage::Event`.

**Impact**: PTY output chopped into fragments - terminal rendering broken.

### P1: Architecture Mismatch

**pty.rs** → `Receiver<Bytes>` channel
**session.rs** → Converts to `StreamReader`
**stream.rs** → Reads but treats each read as message

**Issue**: Channel-based semantics don't match stream-based PTY output.

## Correct Implementations

### ✅ QUIC → PTY (stream.rs Lines 86-106)
Uses `read_exact()` correctly with length prefix:
```rust
recv.read_exact(&mut len_buf).await?;
let len = u32::from_be_bytes(len_buf) as usize;
recv.read_exact(&mut data).await?;
```

### ✅ MessageCodec (codec.rs)
Length-prefixed format implemented correctly.

## Issues by File

### stream.rs

| Line | Severity | Issue |
|------|----------|-------|
| 40 | **CRITICAL** | `pty.read()` → chopped messages |
| 48-50 | **CRITICAL** | Each read = 1 NetworkMessage |
| 118-119 | Low | TODO resize handling |

### pty.rs

| Line | Severity | Issue |
|------|----------|-------|
| 95 | Low | `blocking_send()` - OK in spawn_blocking |
| 213-218 | Medium | Dummy receiver for MVP |

### session.rs

| Line | Severity | Issue |
|------|----------|-------|
| 173 | **MEDIUM** | `outputs.remove()` - single use design flaw |

## SSH Pattern Compliance

| Component | Status | Notes |
|-----------|--------|-------|
| QUIC → PTY | ✅ | Frame-based, correct |
| PTY → QUIC | ❌ | NOT SSH-compliant |
| Message boundaries | ❌ | Chopped into fragments |

## Recommendations

### Priority 1 (CRITICAL)
1. Fix `pump_pty_to_quic()`: Proper framing or raw stream
2. Fix `get_pty_reader()`: Don't remove receiver

### Priority 2
3. Implement `subscribe_output()` for multi-consumer
4. Handle PTY resize (TODO)
