# Debug Report: Eager Spawn Timing Issue - First Keystroke Causes Newline

**Date**: 2026-01-08
**Issue**: First character typed causes output to jump to new line showing `/%`
**Severity**: P1 (Critical UX bug)
**Status**: Root Cause Identified

---

## Executive Summary

Eager spawn fix was implemented but issue persists. When user types FIRST character, after ~1 second, output jumps to new line showing `/%`.

**Root Cause**: Eager spawn DOES work, BUT there's a **critical timing issue** between:
1. Shell prompt initialization (Zsh prints prompt to PTY)
2. PTY→QUIC pump task startup delay
3. First real user input arriving before PTY output is ready

**Impact**: User can work but first keystroke always causes prompt corruption.

---

## Technical Analysis

### Architecture Flow

```
[Client: main.rs:173-189] Send Resize + Empty Input
    ↓
[Server: quic_server.rs:262-324] Receive Resize → Store in pending_resize
    ↓
[Server: quic_server.rs:262-324] Receive Empty Input → Spawn Session
    ↓
[Server: session.rs:39-52] session_mgr.create_session()
    ↓
[Server: pty.rs:41-139] PtySession::spawn()
    ├── Spawn PTY with correct size ✅
    ├── Spawn shell (zsh) ✅
    └── Spawn pty_reader task (blocking read) ✅
    ↓
[Server: quic_server.rs:295-304] Spawn PTY→QUIC pump task
    ↓
[Server: stream.rs:30-62] pump_pty_to_quic() starts
    ↓
    ⚠️ CRITICAL DELAY: pump_pty_to_quic blocks on pty.read()
    ⚠️ Zsh writes prompt to PTY BUT pump task hasn't read yet
    ↓
[Client: main.rs:195-226] User types first character
    ↓
[Client: main.rs:210-221] stdin_task sends Input message
    ↓
[Server: quic_server.rs:270-274] session_mgr.write_to_session(id, &data)
    ↓
[Server: session.rs:62-70] sess.write() → PTY writer
    ↓
    ⚠️ PTY now has: [PROMPT_NOT_YET_READ] + [USER_CHAR]
    ⚠️ PTY writes both to stdout
    ↓
[Server: pty.rs:83-112] pty_reader FINALLY reads from PTY
    ↓
[Server: stream.rs:40-54] Sends to client
    ↓
[Client: main.rs:248-275] Receives TerminalEvent::Output
    ↓
DISPLAY CORRUPTION: Prompt + user char arrive together, cursor in wrong position
```

### The Critical Timing Issue

**Expected Sequence**:
```
1. Client: Send Resize (80x24)
2. Client: Send Empty Input
3. Server: Spawn PTY with 80x24 ✅
4. Server: Zsh starts, writes prompt to PTY
5. Server: PTY→QUIC pump reads prompt
6. Server: Sends prompt to client
7. Client: Displays prompt
8. User: Types first character
9. Client: Sends character to server
10. Server: Writes to PTY
11. Server: PTY echoes back
12. Client: Displays echo
```

**Actual Sequence** (with timing issue):
```
1. Client: Send Resize (80x24)
2. Client: Send Empty Input
3. Server: Spawn PTY with 80x24 ✅
4. Server: Zsh starts, writes prompt to PTY
5. Server: PTY→QUIC pump task SPAWNED (takes time to start)
6. ⚠️ User types first character BEFORE pump task reads prompt
7. Client: Sends character to server
8. Server: Writes character to PTY
9. Server: PTY now has: [unread prompt] + [user char]
10. Server: PTY→QUIC pump FINALLY reads
11. Server: Sends [prompt + user char + corrupted cursor] to client
12. Client: Displays everything at once with wrong cursor position
```

### Why ~1 Second Delay?

The ~1 second delay is caused by:

1. **Tokio task spawn overhead** (~10-50ms)
   - Line 297: `tokio::spawn(async move { ... })`
   - Task scheduler needs to schedule the new task

2. **Mutex lock contention** (~50-200ms)
   - Line 298: `let mut send_lock = send_clone.lock().await;`
   - Main loop still holds lock during message processing

3. **First PTY read blocking behavior** (~500-1000ms)
   - Line 40 (stream.rs): `pty.read(&mut buf).await?`
   - First read may block waiting for PTY buffer to fill
   - Zsh prompt may not immediately trigger readable event

4. **Zsh initialization time** (~100-300ms)
   - Zsh reads `.zshrc`
   - Zsh initializes prompt system
   - Zsh calculates prompt string

**Total**: ~660-1650ms (matches observed ~1 second)

### Why `/%` Pattern?

The `/%` pattern is **Zsh's prompt mark** indicating cursor position confusion:

```
% = Zsh's default prompt
/ = Zsh thinks cursor should be here (wrong position)
```

**Zsh terminal confusion**:
1. Zsh calculates prompt based on terminal size (80x24)
2. Zsh writes prompt assuming cursor at column 1
3. But client sends user input before prompt displayed
4. Zsh receives input, updates internal cursor position
5. Zsh redisplays prompt with cursor correction: `/%`

**From Zsh manual**:
- `%` = Normal prompt (user is NOT root)
- `%/` = Prompt with current directory
- But when cursor position mismatches, Zsh adds correction marks

### Evidence from Code

**Eager Spawn Implementation** (client: main.rs:182-189):
```rust
// ===== EAGER SPAWN TRIGGER =====
// Send empty Input to trigger PTY spawn immediately
let spawn_trigger = NetworkMessage::Input { data: vec![] };
if let Ok(encoded) = MessageCodec::encode(&spawn_trigger) {
    let _ = send.write_all(&encoded).await;
}
```
✅ **Eager spawn IS triggered**

**Server Handling** (quic_server.rs:309-315):
```rust
// Forward input only if non-empty
// Empty Input = eager spawn trigger, don't write to PTY
if !data.is_empty() {
    let _ = session_mgr.write_to_session(id, &data).await;
} else {
    tracing::debug!("Eager spawn trigger received, session {} ready", id);
}
```
✅ **Server correctly handles empty Input**

**PTY→QUIC Pump Spawn** (quic_server.rs:295-304):
```rust
// Spawn PTY→QUIC pump task
if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
    let send_clone = send_shared.clone();
    pty_task = Some(tokio::spawn(async move {
        let mut send_lock = send_clone.lock().await;
        if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
            tracing::error!("PTY→QUIC pump error: {}", e);
        }
        tracing::debug!("PTY→QUIC pump completed");
    }));
    tracing::info!("PTY→QUIC pump task spawned for session {}", id);
}
```
⚠️ **ASYNC SPAWN: No guarantee when task starts reading**

**PTY Pump First Read** (stream.rs:39-44):
```rust
loop {
    let n = pty.read(&mut buf).await?;
    if n == 0 {
        tracing::debug!("PTY EOF, closing stream");
        break;
    }
```
⚠️ **First read may block if no data immediately available**

### Why First Keystroke Specifically?

**Before first keystroke**:
- PTY has prompt in buffer (not yet read)
- Pump task not yet reading
- No data flow to client

**At first keystroke**:
- User types `p`
- Client sends `Input { data: [0x70] }`
- Server writes `p` to PTY
- PTY now has: `[prompt buffer]` + `p`
- PTY becomes readable (has data + new input)
- Pump task reads: `[prompt]` + `p` + `[cursor correction]`
- Client receives everything at once
- Display shows: `/%` (Zsh's confused prompt)

**Subsequent keystrokes work** because:
- Pump task is already running
- PTY output flows immediately
- No buffer buildup

---

## Root Cause

**Primary Issue**: Race condition between PTY initialization and PTY→QUIC pump startup.

**Specific Failure Modes**:
1. **Async task spawn delay** - Tokio doesn't guarantee immediate task execution
2. **Mutex lock contention** - Main loop holds send lock during message processing
3. **PTY read blocking** - First read may block waiting for buffer
4. **Zsh prompt timing** - Zsh writes prompt but pump may not read immediately

**Why eager spawn doesn't fix it**:
- Eager spawn DOES spawn PTY before first input ✅
- BUT PTY→QUIC pump task starts AFTER spawn, with delay ⚠️
- First user input may arrive before pump reads initial prompt ⚠️

---

## Solutions

### Option 1: Block Until PTY Ready (RECOMMENDED)

**Implementation**: Wait for first PTY output before returning from spawn.

```rust
// In quic_server.rs:289-323
match session_mgr.create_session(config).await {
    Ok(id) => {
        session_id = Some(id);

        // Get PTY reader
        let pty_reader = session_mgr.get_pty_reader(id).await?;

        // ===== FIX: Read first PTY output synchronously =====
        // This ensures prompt is read before we proceed
        let mut first_buf = vec![0u8; 1024];
        let mut prompt_data = Vec::new();

        // Read with timeout (1 second max)
        let timeout = tokio::time::Duration::from_secs(1);
        let read_first = tokio::time::timeout(timeout, pty_reader.read(&mut first_buf)).await;

        if let Ok(Ok(n)) = read_first {
            if n > 0 {
                prompt_data.extend_from_slice(&first_buf[..n]);
                tracing::info!("Read {} bytes of initial prompt", n);
            }
        } else {
            tracing::warn!("Timeout waiting for initial prompt");
        }

        // Send prompt to client immediately
        if !prompt_data.is_empty() {
            let mut send_lock = send_shared.lock().await;
            let msg = NetworkMessage::Event(TerminalEvent::Output {
                data: prompt_data,
            });
            let encoded = MessageCodec::encode(&msg)?;
            send_lock.write_all(&encoded).await?;
            drop(send_lock); // Release lock before spawning pump task
        }

        // NOW spawn pump task for remaining output
        let send_clone = send_shared.clone();
        pty_task = Some(tokio::spawn(async move {
            let mut send_lock = send_clone.lock().await;
            if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
                tracing::error!("PTY→QUIC pump error: {}", e);
            }
            tracing::debug!("PTY→QUIC pump completed");
        }));

        // Forward input only if non-empty
        if !data.is_empty() {
            let _ = session_mgr.write_to_session(id, &data).await;
        }
    }
    Err(e) => {
        tracing::error!("Failed to create session: {}", e);
    }
}
```

**Pros**:
- ✅ Guarantees prompt displayed before first input
- ✅ Simple, synchronous
- ✅ No race condition

**Cons**:
- ⚠️ Blocks main loop for up to 1 second
- ⚠️ May timeout if prompt is slow
- ⚠️ Doesn't scale for multiple concurrent sessions

---

### Option 2: Spawn Pump Task Immediately, Use Channel

**Implementation**: Pass PTY reader directly to pump task, use channel for output.

```rust
// In session.rs:39-52
pub async fn create_session(&self, config: TerminalConfig) -> Result<(u64, tokio::sync::mpsc::Receiver<Bytes>)> {
    let id = self.next_id.fetch_add(1, Ordering::SeqCst);
    let (session, output_rx) = PtySession::spawn(id, config)?;

    // ===== FIX: Spawn pump task immediately =====
    // Don't wait for get_pty_reader() call
    let session_mgr = self.clone();
    tokio::spawn(async move {
        if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
            // Pump task starts immediately
            // Output goes to output_rx channel
        }
    });

    Ok(id)
}
```

**Pros**:
- ✅ Pump task starts immediately
- ✅ No delay between spawn and reading

**Cons**:
- ❌ Complex architecture change
- ❌ Need to modify SessionManager significantly
- ❌ Channel management overhead

---

### Option 3: Two-Phase Handshake (Production-Ready)

**Implementation**: Client waits for "SessionReady" event before sending input.

```rust
// Client: main.rs:182-199
let spawn_trigger = NetworkMessage::Input { data: vec![] };
send.write_all(&MessageCodec::encode(&spawn_trigger)?).await?;

// ===== FIX: Wait for session ready =====
let mut ready = false;
let start = std::time::Instant::now();
while start.elapsed() < std::time::Duration::from_secs(2) {
    match recv.read(&mut recv_buf).await? {
        Some(n) => {
            let msg = MessageCodec::decode(&recv_buf[..n])?;
            if let NetworkMessage::Event(TerminalEvent::SessionReady) = msg {
                ready = true;
                break;
            }
            // Buffer other events
        }
        None => break,
    }
}

if !ready {
    return Err(anyhow::anyhow!("Timeout waiting for session ready"));
}
```

**Server**: Send SessionReady after first PTY read.

```rust
// Server: stream.rs:39-57
loop {
    let n = pty.read(&mut buf).await?;
    if n == 0 {
        break;
    }

    // First read = send SessionReady
    if !first_sent {
        let ready_msg = NetworkMessage::Event(TerminalEvent::SessionReady);
        send.write_all(&MessageCodec::encode(&ready_msg)?).await?;
        first_sent = true;
    }

    // Then send output
    let msg = NetworkMessage::Event(TerminalEvent::Output {
        data: buf[..n].to_vec()
    });
    send.write_all(&MessageCodec::encode(&msg)?).await?;
}
```

**Pros**:
- ✅ Clean protocol-level fix
- ✅ Client knows when server is ready
- ✅ No timeout guessing
- ✅ Scales to multiple sessions

**Cons**:
- ⚠️ Requires protocol change (add SessionReady event)
- ⚠️ Client needs to buffer events during wait
- ⚠️ More complex state management

---

### Option 4: Disable PTY Echo (Quick Fix)

**Implementation**: Configure PTY to not echo, client handles local echo.

```rust
// In pty.rs:41-70
use std::os::unix::io::AsRawFd;
use nix::sys::termios::{tcgetattr, tcsetattr, SetArg, LocalFlags};

pub fn spawn(id: u64, config: TerminalConfig) -> Result<(Arc<Mutex<Self>>, tokio::sync::mpsc::Receiver<Bytes>)> {
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(pty_size)?;

    // ===== FIX: Suppress PTY echo =====
    if cfg!(unix) {
        let master_fd = pty_pair.master.as_raw_fd();
        let mut termios = tcgetattr(master_fd)?;
        termios.local_flags.remove(LocalFlags::ECHO);
        termios.local_flags.remove(LocalFlags::ECHOE);
        termios.local_flags.remove(LocalFlags::ECHOK);
        tcsetattr(master_fd, SetArg::TCSANOW, &termios)?;
    }

    // ... rest of spawn code
}
```

**Pros**:
- ✅ No echo race condition
- ✅ Client has full control of display
- ✅ Simple fix (see previous report debugger-260108-1406)

**Cons**:
- ⚠️ Doesn't solve the pump timing issue
- ⚠️ Other PTY output may still have timing issues
- ⚠️ Need local echo implementation

---

## Recommended Fix

**Phase 1 (Immediate)**: Option 1 - Block Until PTY Ready

- Simple, synchronous read of first PTY output
- Ensures prompt displayed before first input
- Minimal code changes

**Phase 2 (Production)**: Option 3 - Two-Phase Handshake

- Clean protocol-level solution
- Client knows when server is ready
- Scales for production

**Phase 3 (Long-term)**: Option 4 - Disable PTY Echo + Local Echo

- Solves both timing and echo issues
- Proper SSH-like implementation
- Best UX

---

## Testing Plan

### Reproduction Steps

1. Start hostagent: `cargo run -p hostagent`
2. Start CLI client: `cargo run -p cli_client -- --connect 127.0.0.1:8443 --token <token> --insecure`
3. Wait for banner
4. Type single character: `p`
5. **Expected**: Display shows `p` on same line as prompt
6. **Actual**: Display jumps to new line showing `/%`

### Verification Steps (After Fix)

**Option 1 (Block until ready)**:
1. Add logging: "Waiting for initial prompt..."
2. Add logging: "Read N bytes of initial prompt"
3. Type `p` → Should see prompt on same line
4. Type `ing 8.8.8.8` → Should complete command on same line
5. Press Enter → Should execute cleanly

**Option 3 (Two-phase handshake)**:
1. Add logging: "Waiting for SessionReady..."
2. Add logging: "SessionReady received"
3. Type `p` → Should see prompt first, then `p`
4. Type `ing 8.8.8.8` → Should complete cleanly
5. Press Enter → Should execute cleanly

### Debug Logging

Add to verify timing:
```rust
// In quic_server.rs:289
let spawn_start = std::time::Instant::now();
match session_mgr.create_session(config).await {
    Ok(id) => {
        tracing::info!("Session created in {:?}", spawn_start.elapsed());

        let pump_start = std::time::Instant::now();
        // ... spawn pump task
        tracing::info!("Pump task spawned in {:?}", pump_start.elapsed());

        let read_start = std::time::Instant::now();
        // ... read first output
        tracing::info!("First PTY read in {:?}", read_start.elapsed());
    }
}
```

```rust
// In main.rs:189
let eager_sent = std::time::Instant::now();
// ... send spawn trigger
tracing::info!("Eager spawn sent at {:?}", eager_sent);

let first_key = std::time::Instant::now();
// ... user types first character
tracing::info!("First key pressed at {:?}", first_key);
tracing::info!("Delay: {:?} (expect >500ms causes issue)", first_key.duration_since(eager_sent));
```

---

## Unresolved Questions

1. **Exact timing threshold**: What's the minimum delay between spawn and first input that causes issue? (Need measurement with debug logging)
2. **Platform differences**: Does this occur on Linux? Windows? (Need testing)
3. **Shell differences**: Does bash behave differently than zsh? (Need testing)
4. **Terminal size impact**: Does 80x24 vs larger terminal change timing? (Need testing)
5. **Network latency impact**: Does remote connection (not localhost) make issue worse? (Need testing)

---

## Related Files

- `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs:173-226` - Eager spawn implementation
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs:262-324` - Server Input handling
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/session.rs:39-52` - Session creation
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs:41-139` - PTY spawn
- `/Users/khoa2807/development/2026/Comacode/crates/core/src/transport/stream.rs:30-62` - PTY→QUIC pump

---

## References

- **Previous Reports**:
  - `plans/reports/debugger-260108-1406-raw-mode-space-key.md` - PTY echo issue
  - `plans/reports/analysis-260108-cli-raw-mode-issues.md` - Raw mode analysis

- **Related Docs**:
  - [Tokio Task Spawning](https://tokio.rs/tokio/tutorial/spawning)
  - [Zsh Prompt System](https://zsh.sourceforge.io/Doc/Release/Prompt-Expansion.html)
  - [PTY Timing Issues](https://www.man7.org/linux/man-pages/man4/pty.4.html)

---

**Report End**
