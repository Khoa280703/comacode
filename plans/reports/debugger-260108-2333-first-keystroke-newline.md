# Debug Report: First Keystroke Causes Unexpected Newline

**Date**: 2026-01-08
**Issue**: FIRST keystroke after connecting causes output to jump to new line
**Severity**: P0 (Critical UX bug)
**Status**: Root Cause Identified

---

## Executive Summary

User connects to QUIC server, sees welcome banner, then types FIRST character → output unexpectedly jumps to new line before showing the shell prompt.

**Root Cause**: Welcome banner ends with `\r\n` + PTY shell startup outputs prompt + carriage return, creating cursor position desync. The FIRST keystroke triggers lazy PTY spawn, and shell prompt output arrives AFTER banner, causing line jump.

**Impact**: Poor UX - user expects to type after banner but gets unexpected newline.

---

## Technical Analysis

### Exact Sequence of Events

```
TIMELINE: First Keystroke Problem

T0: Client connects
    ├── Send Hello
    └── Receive Hello response

T1: Display Welcome Banner (main.rs:154-168)
    ├── Set window title: \x1b]0;Comacode Remote Session\x07
    ├── Print banner:
    │   \r\n
    │   ╔════════════════════════════════════════╗\r\n
    │   ║       🚀  COMACODE REMOTE SHELL        ║\r\n
    │   ╚════════════════════════════════════════╝\r\n
    │   Host: 127.0.0.1:8443\r\n
    │   Press /exit to disconnect\r\n
    └── CRITICAL: Banner ends with \r\n (line 163-164)

T2: Enable Raw Mode (main.rs:171)
    └── RawModeGuard::enable()

T3: Send Resize Message (main.rs:173-180)
    ├── Get terminal size: size() → (cols, rows)
    ├── Create: NetworkMessage::Resize { rows, cols }
    └── Send to server BEFORE any input

T4: Server Receives Resize (quic_server.rs:379-388)
    ├── session_id is None (no session yet)
    └── Store in pending_resize: Option<(rows, cols)>

T5: User Types FIRST Character (e.g., 'l' for 'ls')
    ├── stdin.read() returns [0x6C] (line 195)
    ├── Encode as NetworkMessage::Input { data: [0x6C] } (line 206-208)
    └── Send to server (line 238)

T6: Server Receives First Input (quic_server.rs:262-318)
    ├── session_id is None → LAZY SPAWN TRIGGERED
    ├── Apply pending_resize to config (line 283-286)
    ├── session_mgr.create_session(config) (line 289)
    │   └── PtySession::spawn() → spawns shell (e.g., /bin/bash)
    ├── Spawn PTY→QUIC pump task (line 297-303)
    └── Forward initial input: write_to_session(id, &[0x6C]) (line 310)

T7: PTY Shell Starts (pty.rs:41-64)
    ├── Open PTY with size from pending_resize
    ├── Spawn shell command: /bin/bash -i
    ├── Shell initializes:
    │   ├── Reads ~/.bashrc
    │   ├── Sets PS1 prompt
    │   └── Outputs PROMPT to PTY
    └── PTY reader starts (line 79-112)

T8: PTY Outputs Shell Prompt (pty.rs:83-104)
    ├── Shell writes: "user@host:~$ " (or similar)
    ├── PTY reader reads prompt bytes
    ├── Send via output_tx channel
    └── pump_pty_to_quic forwards to client

T9: Client Receives PTY Output (main.rs:243-270)
    ├── recv.read() returns NetworkMessage::Event(TerminalEvent::Output)
    ├── Data contains: Shell prompt bytes
    └── stdout.write_all(&data) writes prompt

T10: DISPLAY CORRUPTION OCCURS
    ├── Banner ended at: ...Press /exit to disconnect\r\n
    ├── Cursor position: At beginning of NEW line (after \r\n)
    ├── PTY prompt arrives: "user@host:~$ "
    ├── Prompt written to stdout
    ├── User's typed 'l' ECHOED BACK by PTY
    └── Result: Prompt appears on NEW line, not after banner
```

### The Critical Problem

**Banner Layout**:
```
\r\n
╔════════════════════════════════════════╗\r\n
║       🚀  COMACODE REMOTE SHELL        ║\r\n
╚════════════════════════════════════════╝\r\n
Host: 127.0.0.1:8443\r\n
Press /exit to disconnect\r\n     <-- Banner ends with \r\n
[CURSOR HERE]                       <-- Cursor at start of new line
```

**After First Keystroke**:
```
Press /exit to disconnect\r\n
user@host:~$ l                      <-- Prompt + echoed 'l' on new line
```

**What User Expected**:
```
Press /exit to disconnect\r\n
user@host:~$ [CURSOR HERE]          <-- Prompt on SAME line, ready for input
```

---

## Root Cause Analysis

### Issue 1: Lazy Session Spawn Pattern

**Current Design** (quic_server.rs:262-318):
```rust
NetworkMessage::Input { data } => {
    if let Some(id) = session_id {
        // Session exists → forward input
        session_mgr.write_to_session(id, &data).await;
    } else {
        // NO session yet → LAZY SPAWN on first input
        let mut config = TerminalConfig::default();
        if let Some((rows, cols)) = pending_resize.take() {
            config.rows = rows;
            config.cols = cols;
        }
        session_mgr.create_session(config).await?;
        // ...
    }
}
```

**Problem**: Shell prompt outputs AFTER banner, not BEFORE.

**Why This Causes Newline**:
1. Banner displayed: `Press /exit to disconnect\r\n`
2. Cursor at start of new line
3. User types first character → triggers PTY spawn
4. Shell starts → outputs prompt
5. Prompt written to stdout → appears on new line

### Issue 2: Banner Ends with `\r\n`

**Location**: `main.rs:158-168`
```rust
let banner = format!(
    "\r\n\
    \x1b[1;32m╔════════════════════════════════════════╗\x1b[0m\r\n\
    ...
    \x1b[90m  Press /exit to disconnect\x1b[0m\r\n",  <-- Ends with \r\n
    args.connect
);
```

**Problem**: `\r\n` moves cursor to new line, but no prompt follows yet.

### Issue 3: Shell Prompt Output Timing

**PTY Shell Startup Sequence**:
```
1. Shell process spawned
2. Shell reads initialization files (~/.bashrc, /etc/bash.bashrc)
3. Shell sets terminal modes (echo, raw/cooked, etc.)
4. Shell outputs PROMPT: PS1 variable value
5. Shell waits for input
```

**When Does Prompt Appear?**
- Prompt appears AFTER shell initialization
- Shell initialization takes 10-100ms
- During this time, banner is displayed
- User types first character
- Shell finishes init → outputs prompt
- Prompt appears AFTER user already started typing

### Issue 4: PTY Echo Interaction

**What Happens to First Character?**
```
User types: 'l' (0x6C)
    ↓
Client sends: Input { data: [0x6C] }
    ↓
Server writes to PTY: [0x6C]
    ↓
PTY receives [0x6C] → shell buffers it
    ↓
PTY echoes back: [0x6C] (if ECHO enabled)
    ↓
Client receives: Output { data: [0x6C] }
    ↓
Client writes to stdout: [0x6C]
```

**Timing**:
1. Shell prompt arrives: "user@host:~$ "
2. PTY echo arrives: "l"
3. Display shows: "user@host:~$ l"

**But User Expected**:
1. Shell prompt: "user@host:~$ "
2. User types: "l"
3. Display shows: "user@host:~$ l"

---

## Why Previous Fixes Didn't Work

### Fix Attempt 1: Send Resize Before Input (Already Done)

**Location**: `main.rs:173-180`
```rust
if let Ok((cols, rows)) = size() {
    let resize_msg = NetworkMessage::Resize { rows, cols };
    send.write_all(&encoded).await;
}
```

**Status**: ✅ Already implemented
**Problem**: Doesn't solve lazy spawn timing issue

### Fix Attempt 2: Remove Dummy Enter (Already Done)

**Location**: `main.rs:182-184` (commented out)
```rust
// ===== NO DUMMY ENTER =====
// Let PTY naturally print prompt when ready
// Sending \r here causes scroll + display issues
```

**Status**: ✅ Correctly removed
**Problem**: Doesn't solve prompt-after-banner issue

### Fix Attempt 3: Pure Passthrough (Already Done)

**Location**: `main.rs:250-255`
```rust
TerminalEvent::Output { data } => {
    // PURE PASSTHROUGH: SSH does NOT modify output
    let mut stdout = std::io::stdout();
    let _ = stdout.write_all(&data);
    let _ = stdout.flush();
}
```

**Status**: ✅ Already pure passthrough
**Problem**: Passthrough means PTY prompt appears exactly where PTY sends it

---

## The REAL Root Cause

**Banner is displayed BEFORE PTY exists.**

Sequence:
```
1. Connect → Show banner (no PTY yet)
2. Send resize (no PTY yet)
3. User types → PTY spawned
4. PTY outputs prompt
5. Prompt appears AFTER banner
```

**Why This Causes Newline**:
- Banner ends with `\r\n`
- Cursor at start of new line
- PTY prompt written to current cursor position
- Result: Prompt on new line after banner

---

## Solution Analysis

### Option 1: Remove Trailing `\r\n` from Banner (QUICK FIX)

**Implementation**:
```rust
// Change line 163-164 from:
\x1b[90m  Press /exit to disconnect\x1b[0m\r\n

// To:
\x1b[90m  Press /exit to disconnect\x1b[0m  <-- No \r\n
```

**Pros**:
- ✅ One-line fix
- ✅ Prompt will appear on same line as "Press /exit to disconnect"

**Cons**:
- ❌ Cursor will be at end of "Press /exit to disconnect"
- ❌ Prompt will overwrite "Press /exit to disconnect"
- ❌ Still not ideal UX

**Verdict**: Doesn't solve problem, just changes it

---

### Option 2: Eager Session Spawn on Connect (RECOMMENDED)

**Implementation**:
```rust
// In main.rs, after handshake complete:
// Send SpawnSession message immediately
let spawn_msg = NetworkMessage::Command(TerminalCommand::new("".to_string()));
send.write_all(&MessageCodec::encode(&spawn_msg)?).await?;

// Then show banner
let banner = format!(...);
stdout.write_all(banner.as_bytes());

// Shell prompt will be ready by the time banner is displayed
```

**Server Side**:
```rust
// Add new message type:
NetworkMessage::SpawnSession => {
    // Spawn PTY immediately, don't wait for input
    let mut config = TerminalConfig::default();
    if let Some((rows, cols)) = pending_resize.take() {
        config.rows = rows;
        config.cols = cols;
    }
    session_mgr.create_session(config).await?;
}
```

**Pros**:
- ✅ PTY spawned before banner
- ✅ Shell prompt ready immediately
- ✅ Prompt appears after banner correctly
- ✅ No lazy spawn delay

**Cons**:
- ❌ Spawns PTY even if user doesn't type (wastes resources)
- ❌ Need to add new message type or use empty Command

**Verdict**: Best UX, minimal overhead

---

### Option 3: Wait for Prompt Before Showing Banner

**Implementation**:
```rust
// After handshake:
// Request PTY spawn
let spawn_msg = NetworkMessage::Command(TerminalCommand::new("".to_string()));
send.write_all(&MessageCodec::encode(&spawn_msg)?).await?;

// Wait for first Output message (this is the prompt)
loop {
    let n = recv.read(&mut recv_buf).await?;
    let msg = MessageCodec::decode(&recv_buf[..n])?;
    if matches!(msg, NetworkMessage::Event(TerminalEvent::Output { .. })) {
        // Got prompt, now show banner
        let banner = format!(...);
        stdout.write_all(banner.as_bytes());
        break;
    }
}
```

**Pros**:
- ✅ Prompt ready before banner
- ✅ Correct cursor position

**Cons**:
- ❌ Complex flow
- ❌ Banner delay (user waits for prompt before seeing banner)
- ❌ Prompt appears before banner (confusing)

**Verdict**: Too complex, poor UX

---

### Option 4: Clear Line After Banner

**Implementation**:
```rust
// After banner:
// Clear line and move cursor to beginning
let _ = std::io::stdout().write_all(b"\r\x1b[K");  // \r = CR, \x1b[K = clear to EOL
let _ = std::io::stdout().flush();
```

**Pros**:
- ✅ Clears "Press /exit to disconnect" line
- ✅ Prompt appears on clean line

**Cons**:
- ❌ Still has timing issue (prompt may arrive later)
- ❌ Banner instruction disappears

**Verdict**: Partial fix, doesn't solve root cause

---

### Option 5: Two-Phase Banner (Alternative Approach)

**Implementation**:
```rust
// Phase 1: Show minimal banner
let banner1 = "\r\n\x1b[1;32m╔════════════════════════════════════════╗\x1b[0m\r\n\
               \x1b[1;32m║       🚀  COMACODE REMOTE SHELL        ║\x1b[0m\r\n\
               \x1b[1;32m╚════════════════════════════════════════╝\x1b[0m\r\n";
stdout.write_all(banner1.as_bytes());

// Phase 2: After PTY spawn, show prompt + instructions
// (Prompt comes from PTY, so just show extra info)
// let info = "\x1b[90mType /exit to disconnect\x1b[0m\r\n";
```

**Pros**:
- ✅ Clean visual separation
- ✅ Prompt has dedicated space

**Cons**:
- ❌ More complex banner logic
- ❌ Still has timing dependencies

**Verdict**: Good UX but more complex

---

## Recommended Solution

**Option 2: Eager Session Spawn on Connect**

### Implementation

**Step 1: Client sends empty Command after handshake**
```rust
// In main.rs, after line 152 (handshake complete):
// Trigger eager PTY spawn by sending empty Input
let spawn_trigger = NetworkMessage::Input { data: vec![] };
let encoded = MessageCodec::encode(&spawn_trigger)?;
send.write_all(&encoded).await?;

// Small delay to let PTY initialize
tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

// Now show banner
let banner = format!(...);
```

**Step 2: Server handles empty Input as spawn trigger**
```rust
// In quic_server.rs:262-318
NetworkMessage::Input { data } => {
    if let Some(id) = session_id {
        // Session exists → forward input
        session_mgr.write_to_session(id, &data).await;
    } else {
        // Empty input → spawn trigger OR first keystroke
        let mut config = TerminalConfig::default();
        if let Some((rows, cols)) = pending_resize.take() {
            config.rows = rows;
            config.cols = cols;
        }
        session_mgr.create_session(config).await?;

        // Spawn PTY→QUIC pump
        if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
            let send_clone = send_shared.clone();
            pty_task = Some(tokio::spawn(async move {
                // ... pump task
            }));
        }

        // Forward input only if non-empty
        if !data.is_empty() {
            session_mgr.write_to_session(id, &data).await;
        }
    }
}
```

**Step 3: Adjust banner to not end with \r\n**
```rust
// Remove trailing \r\n from banner
let banner = format!(
    "\r\n\
    \x1b[1;32m╔════════════════════════════════════════╗\x1b[0m\r\n\
    \x1b[1;32m║       🚀  COMACODE REMOTE SHELL        ║\x1b[0m\r\n\
    \x1b[1;32m╚════════════════════════════════════════╝\x1b[0m\r\n\
    \x1b[90m  Host: {}\x1b[0m\r\n\
    \x1b[90m  Press /exit to disconnect\x1b[0m",  // <-- No trailing \r\n
    args.connect
);
```

### Why This Works

1. **PTY spawned early**: Shell initializes before banner shown
2. **Prompt ready**: By the time banner is displayed, shell prompt is ready
3. **Prompt appears correctly**: Prompt appears on line after banner
4. **No delay for user**: User sees banner + prompt immediately
5. **First keystroke works**: User can type immediately after banner

---

## Testing Plan

### Reproduction Steps

1. Start hostagent: `cargo run -p hostagent`
2. Start CLI client: `cargo run -p cli_client -- --connect 127.0.0.1:8443 --token <token> --insecure`
3. Observe banner display
4. Type FIRST character (e.g., 'l')
5. **Current behavior**: Output jumps to new line
6. **Expected behavior**: Prompt appears after banner, first character appears at prompt

### Verification Steps

After fix:
1. Connect to server
2. Banner appears
3. Shell prompt appears on next line (not jumping)
4. Type 'l' → Character appears at prompt
5. Type 's' → Display shows "ls" at prompt
6. Press Enter → ls command executes
7. Output shows correctly

---

## Unresolved Questions

1. **Lazy vs Eager Spawn**: Is eager spawn acceptable for all use cases? What if user connects but never types?
2. **PTY Initialization Time**: How long does shell take to initialize? Is 100ms delay enough?
3. **Banner Design**: Should banner be removed entirely and rely on PTY prompt?
4. **Platform Differences**: Does this issue occur on Windows? (cmd.exe vs bash)
5. **Resize Timing**: Does resize before PTY spawn cause issues on some terminals?

---

## Related Files

- **Client**: `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs:154-180`
- **Server**: `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs:262-318`
- **PTY**: `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs:41-139`
- **Session**: `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/session.rs:38-52`

---

## References

- **Previous Debug Sessions**:
  - `plans/reports/debugger-260108-1406-raw-mode-space-key.md` (Space key corruption)
  - `plans/reports/analysis-260108-cli-raw-mode-issues.md` (Raw mode issues)

- **Protocol Docs**:
  - `crates/core/src/types/message.rs` (NetworkMessage types)

---

**Report End**
