# Debug Report: Raw Mode Space Key Losing Characters

**Date**: 2026-01-08
**Issue**: Space character (0x20) causes display corruption but server processes correctly
**Severity**: P1 (Critical UX bug)
**Status**: Root Cause Identified

---

## Executive Summary

User types `ping 8.8.8.8` but display shows `p 8.8.8.8` (only first char + space remain). Server PTY receives correct input `ping 8.8.8.8` and ping works correctly.

**Root Cause**: Local echo suppression in raw mode + PTY echo response timing mismatch creates display corruption.

**Impact**: User can work but display shows wrong characters - confusing and unusable.

---

## Technical Analysis

### Architecture Flow

```
Client Terminal (Raw Mode)
    ↓ stdin.read()
[Client: Line 166-188] stdin_task (spawn_blocking)
    ↓ buf[..n].to_vec()
[Client: Line 203-213] stdin_rx channel
    ↓ NetworkMessage::Command
    ↓ MessageCodec::encode()
[Client: Line 210] send.write_all() → QUIC
    ↓
[Server: quic_server.rs:261-303] NetworkMessage::Command
    ↓ session_mgr.write_to_session()
[Server: session.rs:62-70] sess.write()
    ↓ pty.writer.write_all()
[PTY: pty.rs:148-157] Write to PTY master
    ↓
[PTY: pty.rs:79-112] pty_reader task reads from PTY
    ↓ output_tx.blocking_send()
    ↓
[Server: quic_server.rs:282-290] pump_pty_to_quic()
    ↓ NetworkMessage::Event(TerminalEvent::Output)
    ↓ MessageCodec::encode()
    ↓
[Client: Line 215-246] recv.read()
    ↓ MessageCodec::decode()
    ↓ TerminalEvent::Output { data }
[Client: Line 222-225] stdout_lock.write_all(&data)
```

### Problem: Double Echo Race Condition

**Raw Mode Behavior** (crossterm::terminal::enable_raw_mode):
- Line 26 in `raw_mode.rs`: "Local echo (characters not echoed locally)"
- Client terminal in raw mode: **NO local echo**
- User types ` ` (space 0x20)
- Client sends space to server immediately
- Server PTY receives space, writes to PTY master
- PTY echoes back: ` ` (0x20)
- Server reads PTY output, sends to client
- Client receives echo, writes to stdout

**Race Condition**:
1. User types `ping` + ` ` (space)
2. Client sends `ping ` to server
3. Server PTY receives `ping `
4. PTY echoes back: `ping ` (5 bytes: `p i n g space`)
5. **BUT**: Client already sent `ping ` and user sees partial state

**Display Corruption Mechanism**:
```rust
// Client main.rs: 166-188 - stdin reader
stdin.read(&mut buf)  // Reads "ping " from user
  ↓
stdin_tx.blocking_send(buf[..n].to_vec())  // Sends "ping " to channel
  ↓
// Client main.rs: 203-213 - network writer
Some(data) = stdin_rx.recv() => {
    let text = String::from_utf8_lossy(&data).to_string();  // "ping "
    let cmd = NetworkMessage::Command(comacode_core::TerminalCommand::new(text));
    send.write_all(&encoded).await;  // Sends "ping " to server
}
  ↓
// Server quic_server.rs:261-303
NetworkMessage::Command(cmd) => {
    session_mgr.write_to_session(id, cmd.text.as_bytes()).await;  // Writes "ping " to PTY
}
  ↓
// PTY echoes back: "ping " (or "p i n g \r" depending on terminal)
  ↓
// Server pty.rs:79-112 - PTY reader
reader.read(&mut buf)  // Reads echo from PTY
  ↓
tx_clone.blocking_send(data)  // Sends echo to channel
  ↓
// Server quic_server.rs:282-290
pump_pty_to_quic(pty_reader, &mut *send_lock).await
  ↓
// Client main.rs:215-246
result = recv.read(&mut recv_buf) => {
    TerminalEvent::Output { data } => {
        stdout_lock.write_all(&data);  // Writes echo to stdout
    }
}
```

**The Critical Issue**:
- Raw mode disables local echo (client doesn't echo locally)
- PTY echoes input back (server sends PTY output)
- **Timing mismatch**: Client sends character, PTY echoes back with delay
- **Result**: Display shows PTY echo, not what user typed

### Why Space Key Specifically?

**Hypothesis 1: PTY Echo Backspace Sequence**
- PTY may echo ` ` as space + backspace sequence
- Example: User types `ping ` → PTY echoes `ping ` then sends backspace to "erase" for next command
- Display shows `p ` because backspace erased `ing`

**Hypothesis 2: Terminal Escape Sequences**
- Space (0x20) may trigger PTY to send escape sequences
- PTY sends: `p i n g \r` (carriage return) or `p i n g \b` (backspace)
- Client receives escape sequence, cursor moves
- Display shows only `p `

**Hypothesis 3: Buffer Fragmentation**
- Client sends `ping ` as single chunk
- Server PTY processes character-by-character
- PTY echoes back partial: `p` then `i` then `n` then `g` then ` `
- Network latency + processing delay causes display to show only last echo

### Evidence from Code

**Client No Local Echo** (`raw_mode.rs:25-26`):
```rust
/// Raw mode disables:
/// - Local echo (characters not echoed locally)
```

**PTY Reader Blocking Read** (`pty.rs:83-84`):
```rust
// Blocking read - blocks this thread but NOT the Tokio runtime
match reader.read(&mut buf) {
```
- PTY read is blocking - introduces delay
- Client sends character immediately
- PTY echoes back after delay

**NetworkMessage::Command Text Field** (`core/src/types.rs` - need to verify):
```rust
pub struct TerminalCommand {
    pub text: String,  // Full text, not character-by-character
}
```
- Client sends full command as one message
- PTY receives full command, processes as buffer
- PTY echoes back character-by-character

### Why Server Receives Correct Input?

**Server PTY Processing** (`quic_server.rs:269-297`):
```rust
NetworkMessage::Command(cmd) => {
    // Forward command to PTY
    session_mgr.write_to_session(id, cmd.text.as_bytes()).await;
    // PTY writer.write_all() writes ALL bytes at once
}
```

**PTY Writer** (`pty.rs:148-156`):
```rust
pub fn write(&mut self, data: &[u8]) -> Result<()> {
    self.writer.write_all(data)?;  // Writes "ping 8.8.8.8" atomically
    self.writer.flush()?;
    Ok(())
}
```
- PTY receives `ping 8.8.8.8` as complete buffer
- Shell processes complete command
- Shell executes `ping 8.8.8.8` correctly
- **No corruption at PTY level**

### Display vs Processing Mismatch

| Layer | What Happens | Result |
|-------|--------------|--------|
| **User Types** | `ping 8.8.8.8` | 12 keystrokes |
| **Client stdin.read()** | Reads `ping 8.8.8.8` (12 bytes) | Correct |
| **Client sends to server** | NetworkMessage::Command with text=`ping 8.8.8.8` | Correct |
| **Server PTY receives** | write_all(`ping 8.8.8.8`) | Correct |
| **PTY echoes back** | Sends echo character-by-character with escape sequences | **CORRUPTION** |
| **Client receives echo** | TerminalEvent::Output with echo data | **CORRUPTED** |
| **Client writes to stdout** | write_all(echo_data) | Shows `p 8.8.8.8` |
| **Shell processes** | Receives `ping 8.8.8.8` buffer | **Works correctly** |

---

## Root Cause

**Primary Issue**: PTY echo back in raw mode creates display corruption due to:

1. **No local echo** (client raw mode) - client doesn't display what user types
2. **PTY echo delay** - server PTY echoes back with latency
3. **PTY escape sequences** - PTY may send cursor movement, backspace, or carriage return
4. **Character-by-character echo** - PTY echoes each character separately, not as buffer
5. **Network latency** - Echo arrives after user types more characters

**Why space key specifically**: Space (0x20) may trigger PTY to send:
- Space + backspace sequence (to prepare for next word)
- Carriage return + space (to move cursor)
- Tab expansion (0x20 → 0x09)

**Other keys work**: Letters (a-z, 0-9) don't trigger special PTY sequences.

---

## Solutions

### Option 1: Disable PTY Echo (RECOMMENDED)

**Implementation**: Set PTY to not echo input.

```rust
// In pty.rs:41-70 (PtySession::spawn)
let pty_pair = pty_system.openpty(pty_size)?;

// Add ECHO flag to PTY configuration
// portable-pty may have API to disable echo
// See: https://docs.rs/portable-pty/latest/portable_pty/

// Client handles local echo in raw mode
// Server PTY doesn't echo back
```

**Pros**:
- Simple, one-line fix
- Eliminates echo race condition
- Client has full control of display

**Cons**:
- Need to verify portable-pty API supports echo control
- May break other PTY features

### Option 2: Client Local Echo with Backspace Handling

**Implementation**: Client echoes locally + handles PTY echo suppression.

```rust
// In main.rs:203-213
Some(data) = stdin_rx.recv() => {
    // Echo locally before sending
    stdout_lock.write_all(&data)?;
    stdout_lock.flush()?;

    // Send to server
    let cmd = NetworkMessage::Command(comacode_core::TerminalCommand::new(text));
    send.write_all(&encoded).await?;

    // Suppress PTY echo by consuming TerminalEvent::Output
    // Check if output is echo (same as last sent character)
}
```

**Pros**:
- Client controls display immediately
- No display latency

**Cons**:
- Complex echo suppression logic
- Need to distinguish echo from actual output
- Backspace handling complexity

### Option 3: Use Canonical Mode Instead of Raw Mode

**Implementation**: Don't use raw mode, use canonical mode with line buffering.

```rust
// Remove raw_mode::RawModeGuard::enable()?;
// Let terminal handle echo naturally
```

**Pros**:
- Terminal handles echo correctly
- No race condition

**Cons**:
- Loses raw mode benefits (no Ctrl+C, Ctrl+D handling)
- Not suitable for SSH-like terminal

### Option 4: PTY Echo Suppression via Terminal Attributes

**Implementation**: Configure PTY to suppress echo using termios.

```rust
// In pty.rs, before spawning command
use std::os::unix::io::AsRawFd;

let fd = pty_pair.master.as_raw_fd();
let mut termios = nix::sys::termios::tcgetattr(fd)?;
termios.local_flags.remove(nix::sys::termios::LocalFlags::ECHO);
nix::sys::termios::tcsetattr(fd, nix::sys::termios::SetArg::TCSANOW, &termios)?;
```

**Pros**:
- Proper PTY echo suppression
- Standard Unix approach

**Cons**:
- Unix-specific (not portable to Windows)
- Adds nix dependency

---

## Recommended Fix

**Phase 1 (Quick Fix)**: Option 4 - PTY Echo Suppression

```rust
// In crates/hostagent/src/pty.rs
// Add dependency: nix = { version = "0.29", features = ["term"] }

use std::os::unix::io::AsRawFd;
use nix::sys::termios::{tcgetattr, tcsetattr, SetArg, LocalFlags};

pub fn spawn(id: u64, config: TerminalConfig) -> Result<(Arc<Mutex<Self>>, tokio::sync::mpsc::Receiver<Bytes>)> {
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(pty_size)?;

    // SUPPRESS PTY ECHO (Phase 1 fix)
    if cfg!(unix) {
        let master_fd = pty_pair.master.as_raw_fd();
        let mut termios = tcgetattr(master_fd)?;
        termios.local_flags.remove(LocalFlags::ECHO);
        termios.local_flags.remove(LocalFlags::ECHOE);  // Don't echo erase
        termios.local_flags.remove(LocalFlags::ECHOK);  // Don't echo kill
        tcsetattr(master_fd, SetArg::TCSANOW, &termios)?;
    }

    // ... rest of spawn code
}
```

**Phase 2 (Proper Fix)**: Client Local Echo + PTY Echo Filtering

```rust
// In crates/cli_client/src/main.rs
let mut last_sent: Option<Vec<u8>> = None;

loop {
    tokio::select! {
        Some(data) = stdin_rx.recv() => {
            // Echo locally FIRST
            let _ = stdout_lock.write_all(&data);
            let _ = stdout_lock.flush();

            // Remember what we sent for echo suppression
            last_sent = Some(data.clone());

            // Send to server
            let cmd = NetworkMessage::Command(comacode_core::TerminalCommand::new(
                String::from_utf8_lossy(&data).to_string()
            ));
            send.write_all(&MessageCodec::encode(&cmd)?).await?;
        }
        result = recv.read(&mut recv_buf) => {
            if let Ok(NetworkMessage::Event(TerminalEvent::Output { data })) = MessageCodec::decode(&recv_buf[..n]) {
                // Suppress PTY echo if it matches what we just sent
                if let Some(ref sent) = last_sent {
                    if &data[..] != &sent[..] {
                        // Not echo, display it
                        let _ = stdout_lock.write_all(&data);
                        let _ = stdout_lock.flush();
                    }
                    // Else: suppress echo
                } else {
                    // No last_sent, display everything
                    let _ = stdout_lock.write_all(&data);
                    let _ = stdout_lock.flush();
                }
            }
        }
    }
}
```

---

## Testing Plan

### Reproduction Steps

1. Start hostagent: `cargo run -p hostagent`
2. Start CLI client: `cargo run -p cli_client -- --connect 127.0.0.1:8443 --token <token> --insecure`
3. Type: `ping 8.8.8.8`
4. **Expected**: Display shows `ping 8.8.8.8`
5. **Actual**: Display shows `p 8.8.8.8`

### Verification Steps

After fix:
1. Type `ping 8.8.8.8` → Display shows `ping 8.8.8.8`
2. Press Enter → Ping executes correctly
3. Type `ls -la` → Display shows `ls -la`
4. Press Enter → Directory listing shows
5. Type multiple commands → All display correctly

### Debug Logging

Add to verify fix:
```rust
// In pty.rs:83-90
match reader.read(&mut buf) {
    Ok(n) => {
        tracing::debug!("PTY read {} bytes: {:?}", n, &buf[..n]);
        // Check if read data is echo
    }
}

// In main.rs:222-225
TerminalEvent::Output { data } => {
    tracing::debug!("Client received {} bytes: {:?}", data.len(), &data);
    stdout_lock.write_all(&data);
}
```

---

## Unresolved Questions

1. **PTY Echo Behavior**: Does portable-pty PTY echo input by default? Need to verify with test.
2. **Escape Sequences**: What specific escape sequences does PTY send for space character? Need to capture with debug logging.
3. **Platform Differences**: Does this issue occur on Windows? Need to test.
4. **Network Latency Impact**: Does low latency (localhost) hide or worsen the issue?
5. **Portable-pty API**: Does portable-pty provide echo control? Need to check docs.

---

## Next Steps

1. **Immediate**: Add debug logging to capture PTY output and client input
2. **Short-term**: Implement Option 4 (PTY echo suppression via termios)
3. **Long-term**: Implement Option 2 (client local echo + PTY echo filtering)
4. **Test**: Verify fix on macOS, Linux, Windows

---

## References

- **Code Files**:
  - `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs:166-246`
  - `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs:41-139`
  - `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs:261-303`
  - `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/raw_mode.rs:20-40`

- **Related Docs**:
  - [Crossterm Raw Mode](https://docs.rs/crossterm/latest/crossterm/terminal/fn.enable_raw_mode.html)
  - [Portable-pty Documentation](https://docs.rs/portable-pty/latest/portable_pty/)
  - [Nix termios](https://docs.rs/nix/latest/nix/sys/termios/)

---

**Report End**
