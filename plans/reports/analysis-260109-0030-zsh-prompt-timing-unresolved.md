# Analysis Report: Zsh Prompt Timing Issue - UNRESOLVED

**Date**: 2026-01-09
**Issue**: First keystroke causes newline with `/%` marker (Zsh partial line)
**Severity**: P0 - Critical UX bug
**Status**: ❌ UNRESOLVED - **9 fix attempts failed**

---

## Problem Statement

Khi người dùng kết nối và gõ ký tự đầu tiên:
- **Expected**: Prompt hiển thị đúng, ký tự xuất hiện tại vị trí cursor
- **Actual**: Xuống dòng mới, hiển thị `/%` (Zsh partial line marker)

**Reproduction**:
1. Connect: `./dev-test.sh`
2. Wait for banner
3. Type FIRST character (e.g., `p`)
4. Result: Jumps to new line showing `/%`

---

## Root Cause Analysis

### The Core Issue

**Zsh Line Editor (ZLE) position mismatch**:

```
Timeline của vấn đề:
┌─────────────────────────────────────────────────────────────┐
│ T0: Client gửi Resize (147x40)                              │
│ T1: Client gửi Empty Input (trigger spawn)                  │
│ T2: Client gửi Ping (force QUIC flush)                      │
│ T3: Server nhận → spawn PTY với size 147x40 ✅              │
│ T4: Zsh khởi động, đọc .zshrc (~100-300ms)                  │
│ T5: Zsh render prompt CHO 147 cột                           │
│ T6: PTY→QUIC pump task bắt đầu đọc                           │
│ T7: User gõ ký tự đầu tiên                                  │
│ T8: Client gửi Input                                        │
│ T9: Server write vào PTY                                    │
│     └── PTY có: [prompt chưa đọc] + [user input]            │
│ T10: PTY output cả prompt + input + cursor correction       │
│ T11: Client nhận và display → CORRUPTED                     │
└─────────────────────────────────────────────────────────────┘
```

### Why `/%` Appears

```
Zsh's Partial Line Marker:

%  = Zsh default prompt
/  = Cursor position indicator (Zsh thinks cursor is wrong)

Khi Zsh detect cursor position mismatch:
→ Re-render prompt với correction markers
→ Kết quả: %/ hoặc /%
```

---

## All Fix Attempts (All Failed)

### Attempt 1: Resize Before Spawn ✅ Implemented

**Theory**: Áp dụng `pending_resize` vào `TerminalConfig` TRƯỚC khi spawn.

**Code** (`quic_server.rs:283-289`):
```rust
if let Some((rows, cols)) = pending_resize.take() {
    config.rows = rows;
    config.cols = cols;
}
```

**Result**: ❌ Still broken

**Why**: PTY size đúng, Zsh vẫn render prompt sai timing.

---

### Attempt 2: Ping to Force QUIC Flush ✅ Implemented

**Theory**: QUIC batch packets → delay 1.6s. Ping force immediate send.

**Code** (`main.rs:147-149`):
```rust
// Trigger Spawn
let spawn_trigger = NetworkMessage::Input { data: vec![] };
send.write_all(&MessageCodec::encode(&spawn_trigger)?).await?;

// Force QUIC flush
send.write_all(&MessageCodec::encode(&NetworkMessage::ping())?).await?;
```

**Result**: ❌ Still broken

**Why**: Eliminated network delay, but PTY→Zsh timing issue persists.

---

### Attempt 3: Eager Spawn ✅ Implemented

**Theory**: Spawn PTY immediately after handshake, don't wait for first keystroke.

**Code** (`main.rs:135-150`):
```rust
// EAGER SPAWN SEQUENCE
if let Ok((cols, rows)) = size() {
    let resize = NetworkMessage::Resize { rows, cols };
    send.write_all(&MessageCodec::encode(&resize)?).await?;
}

let spawn_trigger = NetworkMessage::Input { data: vec![] };
send.write_all(&MessageCodec::encode(&spawn_trigger)?).await?;
```

**Result**: ❌ Still broken

**Why**: Prompt STILL not ready when user types first char.

---

### Attempt 4: Wait for Prompt (ABANDONED) ❌

**Theory**: Client waits for first Output before spawning stdin task.

**Code**:
```rust
// Wait for session ready
let mut ready = false;
while start.elapsed() < Duration::from_secs(2) {
    match recv.read(&mut recv_buf).await? {
        Some(n) => {
            if matches!(msg, NetworkMessage::Event(TerminalEvent::SessionReady)) {
                ready = true;
                break;
            }
        }
        None => break,
    }
}
```

**Result**: ❌ Severe typing lag (200-500ms per char)

**User feedback**: "cực chậm, gõ cực lag, xoá 1 cái là xoá hết"

**Why**: Blocking wait prevented stdin from reading properly.

---

### Attempt 5: Double-Tap Resize ✅ Implemented

**Theory**: Gửi SIGWINCH 2 lần - 1 lần trước spawn, 1 lần sau spawn.

**Code** (`quic_server.rs:296-309`):
```rust
// DELAYED DOUBLE-TAP RESIZE
if let Some((rows, cols)) = initial_size {
    let mgr_clone = Arc::clone(&session_mgr);
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(300)).await;
        mgr_clone.resize_session(id, rows, cols).await;
    });
}
```

**Result**: ❌ Still broken (tried 100ms, 300ms)

**Why**: Zsh ignores SIGWINCH during initialization.

---

### Attempt 6: Inject COLUMNS/LINES Env Vars (REVERTED) ❌

**Theory**: Ép Zsh biết terminal size qua env vars.

**Code**:
```rust
config.env.push(("COLUMNS".to_string(), cols.to_string()));
config.env.push(("LINES".to_string(), rows.to_string()));
```

**Result**: ❌ Made it WORSE

**Why**: Xung đột giữa env_vars và PTY driver size → line wrap → Zsh confused.

---

### Attempt 7: Remove Env Vars + 300ms Delay ✅ Implemented

**Theory**: Zsh tự đo đạc, tăng delay để Zsh init xong.

**Code**:
```rust
// NO env vars, only PTY size
config.rows = rows;
config.cols = cols;

// 300ms delay before SIGWINCH
tokio::time::sleep(Duration::from_millis(300)).await;
```

**Result**: ❌ Still broken

**Why**: Even 300ms not enough, or Zsh still ignores first SIGWINCH.

---

### Attempt 8: Pincer Movement (Env Vars + Delayed Resize) ✅ Implemented

**Theory**: "Gọng Kìm" - dùng CẢ HAI:
1. Env vars (0ms) → Zsh reads COLUMNS/LINES FIRST
2. Delayed Resize (300ms) → Sync PTY Driver via SIGWINCH

**Code** (`quic_server.rs:276-316`):
```rust
// PINCER MOVEMENT
config.env.push(("COLUMNS".to_string(), cols.to_string()));
config.env.push(("LINES".to_string(), rows.to_string()));

// ... spawn session ...

// Delayed resize
tokio::spawn(async move {
    tokio::time::sleep(Duration::from_millis(300)).await;
    mgr_clone.resize_session(id, rows, cols).await;
});
```

**Result**: ❌ Still broken

**Why**: Zsh vẫn ưu tiên PTY Driver ioctl(TIOCGWINSZ) hơn env vars.

---

### Attempt 9: Banner `\r\x1b[K` (Clear Line) ✅ Implemented

**Theory**: Banner kết thúc dư `\r\n` → con trỏ lơ lửng → Zsh in `%` để reset. Thêm `\r\x1b[K` để về đầu dòng + xóa sạch.

**Code** (`main.rs:117-128`):
```rust
let banner = format!(
    "... Press /exit to disconnect\x1b[0m\r\n\
    \r\x1b[K", // FIX: Về đầu dòng + Xóa sạch dòng
    args.connect
);
```

**Result**: ❌ Still broken

**Why**: Problem không phải ở client banner - là timing giữa PTY spawn và Zsh prompt.

---

## What SSH Does Differently

### SSH Protocol Flow

```
SSH Client connects to server
    ↓
Server spawns PTY immediately
    ↓
Server sends SSH_SMSG_WINDOW_SIZE
    ↓
Client sends ACK with terminal size
    ↓
Server sets PTY size
    ↓
Shell starts with CORRECT size from beginning
    ↓
Shell renders prompt correctly
    ↓
Client starts sending user input
```

**Key Difference**: SSH has **synchronous handshake** for terminal setup before shell starts.

### Our QUIC Protocol Flow

```
Client connects
    ↓
Send Hello + Auth
    ↓
Send Resize message (ASYNC - may arrive before/after shell)
    ↓
Send Empty Input (trigger spawn)
    ↓
Server spawns shell
    ↓
┌─── PROBLEM: Resize timing vs Shell init ───┐
│ Shell starts → reads .zshrc → renders     │
│ Resize message → may be TOO LATE          │
│ SIGWINCH → Zsh may ignore during init     │
└────────────────────────────────────────────┘
    ↓
User types first char
    ↓
PTY outputs prompt + char together → CORRUPTED
```

**Key Problem**: No synchronous terminal setup handshake.

---

## Why This Is Fundamentally Hard

### 1. Asynchronous Message Delivery

QUIC streams are async - Resize, Input, Ping messages:
- May arrive in different orders
- May be batched by Quinn
- No guaranteed timing

### 2. Zsh Initialization Timing

Zsh startup sequence:
1. Parse command line args (~5ms)
2. Read `.zshrc` (~50-200ms)
3. Initialize ZLE (~10-50ms)
4. Set up signal handlers (~10-50ms)
5. **Render FIRST prompt**
6. NOW ready to handle SIGWINCH

**Problem**: Step 5 happens BEFORE step 6 if SIGWINCH sent early.

### 3. PTY Buffer Behavior

PTY output buffer:
- Prompt written by Zsh but not yet read
- User input arrives
- PTY now has: `[prompt] + [input] + [cursor correction]`
- Single read returns everything → client displays corrupted

### 4. No Synchronization Point

Protocol lacks:
- "TerminalReady" message from server
- "AckPrompt" from client
- Any handshake to synchronize states

---

## Remaining Options (Not Yet Tried)

### Option A: Protocol-Level Fix - SessionReady Event

**Implementation**: Add new message type for terminal synchronization.

```rust
// Protocol
pub enum TerminalEvent {
    Output { data: Vec<u8> },
    SessionReady,  // NEW: Signal PTY + prompt ready
}

// Server: Send after first PTY read
loop {
    let n = pty.read(&mut buf).await?;
    if !first_sent {
        send_event(SessionReady).await?;
        first_sent = true;
    }
    send_event(Output { data: buf[..n].to_vec() }).await?;
}

// Client: Wait for SessionReady before spawning stdin
let mut ready = false;
while !ready {
    let msg = recv.read().await?;
    if matches!(msg, Event(SessionReady)) {
        ready = true;
    }
}
// NOW spawn stdin task
```

**Pros**:
- ✅ Proper synchronization
- ✅ Client knows when server ready
- ✅ No race condition

**Cons**:
- ❌ Requires protocol change
- ❌ More complex state management
- ❌ Need to buffer events during wait

**Status**: Not tried

---

### Option B: Server-Side Initial Prompt Read

**Implementation**: Server reads first PTY output synchronously before returning.

```rust
match session_mgr.create_session(config).await? {
    Ok(id) => {
        // Get PTY reader
        let pty_reader = session_mgr.get_pty_reader(id).await?;

        // Read first prompt SYNCHRONOUSLY
        let mut first_buf = vec![0u8; 1024];
        let timeout = Duration::from_secs(1);
        let read_first = timeout(timeout, pty_reader.read(&mut first_buf)).await;

        if let Ok(Ok(n)) = read_first {
            // Send prompt to client IMMEDIATELY
            let msg = NetworkMessage::Event(TerminalEvent::Output {
                data: first_buf[..n].to_vec(),
            });
            send_message(&mut send, &msg).await?;
        }

        // NOW spawn pump task for remaining output
        tokio::spawn(async move {
            pump_pty_to_quic(pty_reader, send).await;
        });
    }
}
```

**Pros**:
- ✅ Simple implementation
- ✅ Guarantees prompt sent first
- ✅ No protocol change

**Cons**:
- ❌ Blocks main loop for up to 1s
- ❌ Doesn't scale for concurrent sessions
- ❌ May timeout if prompt slow

**Status**: Not tried

---

### Option C: Client-Side Prompt Detection

**Implementation**: Client detects prompt pattern, holds input until prompt seen.

```rust
let mut prompt_seen = false;
let mut pending_input: Vec<u8> = Vec::new();

loop {
    tokio::select! {
        Some(bytes) = stdin_rx.recv() => {
            if !prompt_seen {
                // Buffer input until prompt arrives
                pending_input.extend(bytes);
            } else {
                // Send immediately
                send.write_all(&bytes).await?;
            }
        }
        result = recv.read(&mut buf) => {
            match result? {
                Some(n) => {
                    let msg = MessageCodec::decode(&buf[..n])?;
                    if matches!(msg, Event(Output { .. })) {
                        // Check if looks like prompt
                        if looks_like_prompt(&msg) {
                            prompt_seen = true;
                            // Flush pending input
                            if !pending_input.is_empty() {
                                send.write_all(&pending_input).await?;
                                pending_input.clear();
                            }
                        }
                    }
                }
                None => break,
            }
        }
    }
}
```

**Pros**:
- ✅ No server change
- ✅ Works with current protocol

**Cons**:
- ❌ Heuristic-based (may false positive)
- ❌ Complex buffering logic
- ❌ Doesn't solve root timing issue

**Status**: Not tried

---

### Option D: Pre-Warm PTY on Connect

**Implementation**: Spawn PTY immediately on connection, not on first input.

```rust
// In quic_server.rs - handle_connection
async fn handle_connection(incoming: Incoming) -> Result<()> {
    let connection = incoming.accept().await?;

    // Authenticate first
    // ...

    // AFTER auth: IMMEDIATELY spawn PTY
    let config = TerminalConfig::default();
    let session_id = session_mgr.create_session(config).await?;

    // Wait a bit for prompt
    tokio::time::sleep(Duration::from_millis(200)).await;

    // Now connection is "ready"
    // Handle streams...
}
```

**Pros**:
- ✅ PTY ready before any user input
- ✅ Prompt rendered early

**Cons**:
- ❌ Spawns PTY even if user doesn't type (waste)
- ❌ Need size before first Resize message
- ❌ What size to use? Default 80x24 may be wrong

**Status**: Not tried

---

### Option E: Disable Zsh Prompt Optimization

**Implementation**: Configure Zsh to not optimize prompt rendering.

```rust
// In TerminalConfig
config.env.push((
    "ZLE_USE_OLD_PROMPT".to_string(),
    "1".to_string()
));
config.env.push((
    "PROMPT_EOL_MARK".to_string(),
    "".to_string()
));
```

**Pros**:
- ✅ May prevent cursor correction marks
- ✅ Simple config change

**Cons**:
- ❌ Doesn't solve timing, only masks symptom
- ❌ May not work (ZLE behavior)
- ❌ Affects user experience

**Status**: Not tried

---

## Questions Unresolved

1. **Exact timing threshold**: How long after spawn until Zsh reliably handles SIGWINCH?
2. **Platform differences**: Does Linux behave differently than macOS?
3. **Shell differences**: Does bash have same issue as zsh?
4. **Terminal size impact**: Does issue occur with all sizes or only large terminals?
5. **Network latency**: Does remote (non-localhost) connection make it worse?

---

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `quic_server.rs` | 276-316 | Pincer Movement: Env vars + delayed resize |
| `quic_server.rs` | 362-389 | Legacy Command path: same fix |
| `main.rs` | 135-150 | Eager spawn sequence |
| `main.rs` | 147-149 | Ping for QUIC flush |
| `main.rs` | 117-128 | Banner `\r\x1b[K` clear line |

---

## References

- Previous debug reports:
  - `debugger-260108-2338-eager-spawn-timing-issue.md`
  - `debugger-260108-2333-first-keystroke-newline.md`
  - `debugger-260108-1406-raw-mode-space-key.md`

---

**Status**: ❌ UNRESOLVED - Need to try remaining options or different approach.

**Recommendation**: Try **Option A (SessionReady event)** or **Option B (Server-side initial read)** next.
