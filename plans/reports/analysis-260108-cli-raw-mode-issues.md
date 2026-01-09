# CLI Client Raw Mode - Issues Analysis

**Date**: 2026-01-08
**Status**: BLOCKED - Multiple critical bugs
**Component**: `crates/cli_client/src/main.rs`

---

## Current Implementation Approach

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    cli_client (Raw Mode)                │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  stdin (crossterm raw mode)                             │
│      ↓                                                   │
│  spawn_blocking task                                    │
│      ├── Read byte-by-byte: stdin.read(&mut buf)       │
│      ├── Check /exit locally                            │
│      └── Send via mpsc::channel                         │
│                   ↓                                      │
│  tokio::select! main loop                               │
│      ├── Receive from channel                           │
│      ├── Wrap: NetworkMessage::Command(text)           │
│      ├── Encode: MessageCodec                           │
│      └── Send: send.write_all()                         │
│                   ↓                                      │
│  recv.read() → NetworkMessage::Event::Output           │
│      └── stdout.write_all(&data)  (raw PTY output)     │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Key Code Locations

**1. Raw Mode Setup** (`main.rs:158`)
```rust
let _guard = raw_mode::RawModeGuard::enable()?;
// Uses crossterm::terminal::enable_raw_mode()
```

**2. Stdin Reader Task** (`main.rs:166-188`)
```rust
let mut stdin_task = tokio::task::spawn_blocking(move || {
    let mut stdin = std::io::stdin();
    let mut buf = [0u8; 1024];
    loop {
        match stdin.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                // Check /exit locally
                let text = String::from_utf8_lossy(&buf[..n]).to_string();
                if text.trim() == "/exit" { break; }
                // Send through channel
                stdin_tx.blocking_send(buf[..n].to_vec())
            }
        }
    }
});
```

**3. Main Loop - Send to Server** (`main.rs:203-212`)
```rust
Some(data) = stdin_rx.recv() => {
    // Convert bytes → String → Command → NetworkMessage
    let text = String::from_utf8_lossy(&data).to_string();
    let cmd = NetworkMessage::Command(comacode_core::TerminalCommand::new(text));
    let encoded = MessageCodec::encode(&cmd)?;
    send.write_all(&encoded).await
}
```

**4. Server Processing** (`hostagent/src/quic_server.rs:270`)
```rust
TerminalCommand { text } => {
    session_mgr.write_to_session(id, text.as_bytes()).await
    // PTY receives: text.as_bytes()
}
```

---

## Current Bugs

### Bug 1: Space Key Causes Character Loss

**Symptom**: Type `ping` + space → display shows `p` but server receives `ping ` correctly

**Root Cause**:
```
User types: p-i-n-g-[space]
    ↓
stdin.read() reads each byte immediately (raw mode)
    ↓
Each keystroke sent individually via channel
    ↓
Server PTY receives: 'p', 'i', 'n', 'g', ' ' (space)
    ↓
PTY echoes back with escape sequences
    ↓
Client receives PTY echo → writes to stdout
    ↓
DISPLAY CORRUPTION: Space character triggers cursor movement
```

**Why server works but display doesn't**:
- Server PTY receives complete input correctly
- Display shows corrupted PTY echo
- Race condition: local keystroke vs PTY echo

---

### Bug 2: Ctrl+C Not Working

**Symptom**: Ctrl+C during `ping 8.8.8.8` does not stop ping

**Root Cause**:
```
User presses Ctrl+C
    ↓
In raw mode: stdin.read() returns [0x03] (1 byte)
    ↓
String::from_utf8_lossy(&[0x03]) → "\x03" (string with byte 0x03)
    ↓
NetworkMessage::Command("\x03")
    ↓
Server: cmd.text.as_bytes() → [0x03] ✅ Correct byte!
    ↓
BUT: May have timing/race condition issues
```

**Possible Causes**:
1. Tokio::select! race condition
2. Channel buffering delay
3. PTY signal handling timing
4. Or: `/exit` check interfering (line 176)

---

### Bug 3: Cursor Jumps to New Line

**Symptom**: Pressing space after `ping` moves cursor to new line

**Root Cause**:
- Raw mode: Space (0x20) sent as-is
- PTY echoes: Space + carriage return (0x0D)
- Client writes raw PTY output to stdout
- 0x0D moves cursor to beginning of line
- Next character overwrites existing text

---

## Fundamental Architectural Problem

### The Echo Conflict

```
┌─────────────────────────────────────────────────────────────┐
│                    ECHO CONFLICT                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  User Input → [stdin.read()]                               │
│      │                                                       │
│      ├─► Should be LOCAL ECHO (immediate feedback)          │
│      │                                                       │
│      └─► But PTY also ECHOS (delayed, with escapes)        │
│                                                             │
│  Result: Double echo OR corrupted display                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Why SSH Works But This Doesn't

| Aspect | SSH | Current CLI Client |
|--------|-----|-------------------|
| Local Echo | YES (handled by SSH client) | NO (raw mode disables) |
| PTY Echo | Filtered out | Shown raw to user |
| Keystroke Handling | Local line editing | Sent immediately |
| Ctrl+C | Local SIGINT handling | Sent as byte 0x03 |

---

## Solutions Evaluated

### Option 1: Keep Raw Mode + Accept Limitations

**Approach**: Current implementation, accept PTY echo behavior

**Pros**:
- Simple (already implemented)
- Works for TUI programs (vim, htop)

**Cons**:
- ❌ Space key corruption
- ❌ Ctrl+C unreliable
- ❌ Display issues
- ❌ Poor UX for shell usage

**Verdict**: NOT VIABLE for shell usage

---

### Option 2: Hybrid Mode - Detect TUI Programs

**Approach**: Detect when user runs vim/htop → enable raw mode, else cooked mode

**Pros**:
- Best of both worlds
- Shell works normally
- TUI programs still work

**Cons**:
- ❌ Complex to detect all TUI programs
- ❌ Race condition on program switch
- ❌ False negatives/positives

**Verdict**: Too complex, unreliable

---

### Option 3: Proper SSH-like Implementation (RECOMMENDED)

**Approach**: Implement local line editing + local echo, filter PTY echo

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│              SSH-like Client Architecture                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  User Input → Local Line Editor                            │
│      ├── Handle: Backspace, Arrow keys, Ctrl+C             │
│      ├── Local echo to stdout                              │
│      └── On Enter: Send complete line to server            │
│                                                             │
│  PTY Output → Filter out echoed input → Display only       │
│                                                             │
│  Raw mode: Only for TUI programs (auto-detected)           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Pros**:
- ✅ Space/backspace work locally
- ✅ Ctrl+C handled locally (SIGINT)
- ✅ Clean display
- ✅ SSH-like UX

**Cons**:
- ❌ Requires significant rewrite
- ❌ Need to handle all editing keys
- ❌ PTY echo filtering complex

**Effort**: 2-3 days

---

### Option 4: Use Existing SSH Library (QUIC + SSH)

**Approach**: Use `russh` or similar for client, keep QUIC for transport

**Pros**:
- ✅ Battle-tested SSH implementation
- ✅ All edge cases handled
- ✅ Local echo/line editing built-in

**Cons**:
- ❌ Adds heavy dependency
- ❌ May not fit QUIC architecture
- ❌ Overkill for simple terminal

**Effort**: 1-2 days integration

---

## Recommended Approach

**Option 3**: Implement proper SSH-like client with local line editing

### Implementation Plan

#### Phase 1: Local Line Editor (1 day)
```rust
// New module: cli_client/src/line_editor.rs
pub struct LineEditor {
    buffer: String,
    cursor: usize,
}

impl LineEditor {
    pub fn handle_key(&mut self, key: u8) -> KeyAction {
        match key {
            0x03 => KeyAction::Interrupt,  // Ctrl+C
            0x04 => KeyAction::Eof,        // Ctrl+D
            0x7f => KeyAction::Backspace,  // Backspace
            0x0D => KeyAction::Submit,     // Enter
            b' '..=b'~' => KeyAction::Insert(c),
            // ... arrow keys, home, end, etc.
        }
    }
}
```

#### Phase 2: PTY Echo Filter (0.5 day)
```rust
// Track what we sent, filter from PTY output
struct EchoFilter {
    sent_bytes: VecDeque<u8>,
}

impl EchoFilter {
    pub fn filter(&mut self, pty_output: &[u8]) -> Vec<u8> {
        // Remove echoed input from PTY output
        // Return only "new" output
    }
}
```

#### Phase 3: Raw Mode Toggle (0.5 day)
```rust
// Auto-detect TUI programs
if is_tui_command(&line) {
    enable_raw_mode();
    // Pass-through mode for vim/htop
}
```

---

## Immediate Action Required

**Current raw mode implementation is BROKEN for shell usage.**

### Options:

1. **Revert to cooked mode** (line-buffered)
   - Pros: Works reliably for shell
   - Cons: No vim/htop support

2. **Implement Option 3** (SSH-like)
   - Pros: Proper solution
   - Cons: 2-3 days work

3. **Accept limitations**
   - Document that raw mode is for TUI only
   - Use cooked mode for shell commands

---

## Unresolved Questions

1. Why did Ctrl+C work before but not now?
   - Timing change after removing "Connected" message?
   - Race condition introduced?

2. Why does space character specifically cause corruption?
   - Need to capture actual PTY output bytes
   - May be carriage return (0x0D) issue

3. Is this a crossterm-specific issue or generic raw mode problem?

---

## Related Files

- `crates/cli_client/src/main.rs` - Main client loop
- `crates/cli_client/src/raw_mode.rs` - Raw mode guard
- `crates/hostagent/src/quic_server.rs` - Server message handling
- `crates/hostagent/src/session.rs` - PTY write_to_session

---

## References

- [crossterm documentation](https://docs.rs/crossterm/)
- [ssh-rs implementation](https://github.com/alexcrichton/ssh-rs)
- [PTY echo handling](https://www.man7.org/linux/man-pages/man4/pty.4.html)
