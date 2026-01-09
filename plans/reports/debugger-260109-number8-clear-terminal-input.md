# Debug Report: Number '8' Causes Screen Clear in Comacode Terminal

**Date**: 2026-01-09
**Issue**: Typing '8' character (after space) causes screen clear and newline
**Severity**: High - blocks normal terminal usage
**Status**: Investigation in progress

## Executive Summary

User reports that typing space (0x20) works fine, but subsequently typing number '8' (0x38) causes the terminal screen to clear and move to a new line. This is highly unusual because 0x38 is a regular ASCII character, not a control character.

## Problem Statement

**Symptom**: "gõ space xong vẫn bình thường, gõ thêm số 8 là clear hết xong xuống dòng"
- Space (0x20) works normally
- Number 8 (0x38) triggers screen clear + newline

**Context**:
- Recent fix: Backspace filtering (0x08, 0x7F) was added to prevent PTY display corruption
- Issue occurs in `crates/cli_client/src/main.rs` - stdin_task sends input to PTY via QUIC
- Data flow: stdin → Input message → QUIC → server → PTY → echo back → client display

## Investigation

### Code Flow Analysis

#### 1. Client Input (`crates/cli_client/src/main.rs` lines 196-260)

```rust
// Filter out backspace bytes - handle locally, don't send to PTY
let filtered_data: Vec<u8> = data.iter()
    .filter(|&&b| b != 0x08 && b != 0x7F) // Remove BS (0x08) and DEL (0x7F)
    .copied()
    .collect();

// Send filtered bytes
if !filtered_data.is_empty() {
    let msg = NetworkMessage::Input {
        data: filtered_data,
    };
    // ... send to server
}
```

**Observation**: Filter only removes 0x08 and 0x7F. Both space (0x20) and '8' (0x38) pass through unchanged.

#### 2. Server Input Handler (`crates/hostagent/src/quic_server.rs` lines 290-324)

```rust
NetworkMessage::Input { data } => {
    // ...
    if let Some(id) = session_id {
        // Write raw bytes directly to PTY
        if let Err(e) = session_mgr.write_to_session(id, &data).await {
            tracing::error!("Failed to write input to PTY: {}", e);
        }
    }
}
```

**Observation**: Raw bytes written directly to PTY without modification.

#### 3. PTY Write (`crates/hostagent/src/pty.rs` lines 149-159)

```rust
pub fn write(&mut self, data: &[u8]) -> Result<()> {
    use std::io::Write;
    self.writer
        .write_all(data)
        .context("Failed to write to PTY")?;
    self.writer
        .flush()
        .context("Failed to flush PTY writer")?;
    Ok(())
}
```

**Observation**: Standard write to PTY master with flush.

#### 4. PTY Output Pump (`crates/core/src/transport/stream.rs` lines 125-196)

```rust
pub async fn pump_pty_to_quic_smart<R>(
    mut pty: R,
    send: &mut SendStream,
    config: BufferConfig,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
{
    // Smart buffering with flush on newline
    let chunk_has_newline = read_buf[..n].contains(&b'\n');

    // Immediate flush conditions
    let should_flush = if config.flush_on_newline && chunk_has_newline {
        true  // Interactive mode - flush on newline
    } else if batch_buf.len() >= config.max_batch_size {
        true  // Size threshold
    } else {
        false
    };
}
```

**Observation**: Smart buffering flushes on newline. Buffer config is `interactive()` mode.

## Potential Root Causes

### Hypothesis 1: Terminal Escape Sequence Interpretation

**Possibility**: The shell or terminal might interpret " 8" (space followed by 8) as part of an escape sequence.

**Analysis**:
- ANSI escape sequences start with ESC (0x1B)
- Space (0x20) and '8' (0x38) are not ESC
- Unlikely to be escape sequence issue

**Likelihood**: Low

### Hypothesis 2: PTY Canonical Mode Processing

**Possibility**: PTY in canonical mode might have special handling for certain character combinations.

**Analysis**:
- Canonical mode processes line-by-line
- Special characters: EOF (0x04), EOL (0x0A, 0x0D), ERASE (0x08, 0x7F), KILL (0x15), etc.
- '8' (0x38) is not a special character in canonical mode

**Likelihood**: Low

### Hypothesis 3: Shell History Expansion or Substitution

**Possibility**: The shell (bash/zsh) might interpret " 8" as a history expansion or special pattern.

**Analysis**:
- Bash history expansion uses `!`, `!!`, `!n`
- Zsh has similar but different syntax
- Space before '8' should prevent most expansions
- But '8' could be interpreted as job control or other special meaning

**Likelihood**: Medium

### Hypothesis 4: Terminal Control Character in Data Stream

**Possibility**: There might be hidden control characters being sent along with the visible '8'.

**Analysis**:
- Could be multi-byte key sequence (e.g., arrow keys, function keys)
- Vietnamese keyboard input method might send composition characters
- Terminal might be in a mode that sends escape sequences for certain keys

**Likelihood**: **HIGH** - Need to verify with debug logging

### Hypothesis 5: Buffer Corruption or Message Framing Issue

**Possibility**: The QUIC stream message framing might be corrupted, causing '8' to be misinterpreted.

**Analysis**:
- MessageCodec uses length-prefixed framing
- Recent fix resolved double-framing bug
- Current code looks correct

**Likelihood**: Low

## Debugging Actions Taken

### 1. Added Debug Logging

Added `eprintln!` statements to trace raw bytes:

**Client side** (`crates/cli_client/src/main.rs` line 220):
```rust
eprintln!("[DEBUG] Sending to PTY: {:?}", filtered_data);
```

**Server side** (`crates/hostagent/src/quic_server.rs` line 308):
```rust
eprintln!("[SERVER DEBUG] Writing to PTY session {}: {:02X?}", id, data);
```

**PTY output** (`crates/core/src/transport/stream.rs` line 205):
```rust
eprintln!("[DEBUG] PTY output: {:02X?}", data);
```

### 2. Fixed Compilation Error

Fixed missing match arms in `crates/mobile_bridge/src/quic_client.rs`:
- Added `NetworkMessage::RequestPty { .. }`
- Added `NetworkMessage::StartShell`

## Next Steps

### Immediate Actions Required

1. **Run with debug logging enabled**
   ```bash
   # Terminal 1: Start server
   RUST_LOG=trace ./target/release/hostagent

   # Terminal 2: Start client
   ./target/release/cli_client --connect 127.0.0.1:8443 --token <TOKEN>
   ```

2. **Reproduce the issue**
   - Type space (observe debug output)
   - Type '8' (observe debug output and what's actually being sent)

3. **Analyze debug output**
   - Check if '8' (0x38) is sent alone or with extra bytes
   - Check if PTY echoes back anything unusual
   - Look for escape sequences (0x1B) or other control chars

### Expected Debug Output

**Normal case** (typing '8'):
```
[DEBUG] Sending to PTY: [56]           # 56 = 0x38 = '8'
[SERVER DEBUG] Writing to PTY session 1: [38]
[DEBUG] PTY output: [38]                # Echo back
```

**Abnormal case** (if hypothesis correct):
```
[DEBUG] Sending to PTY: [56, 27, 91, 66]  # '8' + ESC + [ + B (down arrow)
[SERVER DEBUG] Writing to PTY session 1: [38, 1B, 5B, 42]
[DEBUG] PTY output: [1B, 5B, 4A, 0A, ...]  # Clear screen + newline
```

## Proposed Fixes

### Fix 1: Explicit Byte Logging (Implement)

Trace exact bytes at each layer to identify where corruption occurs.

### Fix 2: Filter Escape Sequences (If needed)

If terminal is sending escape sequences, filter them at input:
```rust
// Filter terminal escape sequences
let filtered_data: Vec<u8> = data.iter()
    .filter(|&&b| b != 0x08 && b != 0x7F) // Backspace
    .filter(|&&b| b != 0x1B)             // ESC - might start escape seq
    .copied()
    .collect();
```

**Risk**: Might break legitimate escape sequences (arrow keys, etc.)

### Fix 3: Disable PTY Canonical Mode (If needed)

Run PTY in raw mode to prevent shell from interpreting special characters:
```rust
// In pty.rs, when spawning
let mut cmd = CommandBuilder::new(config.shell.clone());
// Set PTY to raw mode
```

**Risk**: Might break line editing, job control, etc.

## Unresolved Questions

1. **What exact bytes are being sent when '8' is typed?**
   - Need debug output to confirm

2. **Is this specific to Vietnamese keyboard layout?**
   - Could be IME (Input Method Editor) sending composition sequences

3. **Does the issue occur with other numbers?**
   - Need to test 0-9, letters, special characters

4. **What shell is being used?**
   - bash/zsh/fish might handle input differently

5. **Is the PTY in canonical or raw mode?**
   - Affects how special characters are processed

6. **Could this be a terminal emulation issue?**
   - xterm, iTerm2, Terminal.app might behave differently

## Related Files

- `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs` - Client stdin handler
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs` - Server Input handler
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs` - PTY session management
- `/Users/khoa2807/development/2026/Comacode/crates/core/src/transport/stream.rs` - PTY↔QUIC pump
- `/Users/khoa2807/development/2026/Comacode/crates/core/src/types/message.rs` - Message definitions

## Git History

Recent commits related to input handling:
- `5cc9879` - fix(cli): filter backspace bytes to prevent PTY display corruption
- `cd440c0` - fix(cli): send raw bytes to PTY, simplify /exit detection
- `ac3a676` - fix(cli): properly intercept /exit command
- `82483e3` - feat(hostagent): restore input logging at trace level

## Conclusion

**Current Status**: Debug logging added, ready for testing

**Most Likely Cause**: Terminal sending multi-byte sequence when '8' is typed (possibly keyboard layout or IME related)

**Next Action**: Run with debug logging and capture actual byte stream

**Timeline**: Awaiting user testing with debug build
