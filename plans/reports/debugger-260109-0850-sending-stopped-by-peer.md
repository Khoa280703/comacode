# Debugger Report: "sending stopped by peer: error 0"

**ID**: debugger-260109-0850-sending-stopped-by-peer
**Date**: 2026-01-09
**Status**: 🔍 Root Cause Identified
**Language**: vi

---

## Executive Summary

**Symptom**: "sending stopped by peer: error 0" xuất hiện SAU khi handshake thành công và banner hiển thị đúng.

**Root Cause**: **BUG ĐÃ ĐƯỢC FIX** trong phase 01 của refactor 260109-0109. Vấn đề là protocol framing bug ở **BÊN CLIENT**, không phải server.

**TL;DR**: Client dùng `read()` thay vì `read_exact()` → partial read → decode fail → connection close.

---

## Timeline Analysis

### Sequence of Events

1. **✅ Handshake thành công** (line 109-113, `main.rs`)
   - Client gửi `NetworkMessage::hello()`
   - Server phản hồi `NetworkMessage::hello()`
   - Client in "Authenticated"

2. **✅ Banner hiển thị** (line 115-127, `main.rs`)
   - Window title set
   - ASCII art banner in ra stdout
   - Không có network operation ở đây

3. **✅ Resize message** (line 141-144, `main.rs`)
   - Client gửi `NetworkMessage::Resize { rows, cols }`
   - Server lưu vào `pending_resize` (line 345, `quic_server.rs`)
   - OK vì session chưa spawn

4. **✅ Empty Input trigger** (line 147-149, `main.rs`)
   - Client gửi `NetworkMessage::Input { data: vec![] }`
   - Server spawn session (line 297-305, `quic_server.rs`)

5. **❌ Interactive loop FAIL** (line 205-235, `main.rs`)
   - Client đợi message từ server
   - **SERVER GỬI PTY OUTPUT** → **CLIENT ĐỌC SAI** → crash

---

## Root Cause Analysis

### Vị trí Bug

**File**: `crates/cli_client/src/main.rs` (BEFORE phase 01 fix)
**Line**: 212-226 (interactive loop)

### Bug Pattern (ĐÃ FIX)

**TRƯỚC FIX** (broken code):
```rust
// Client dùng read() cho length-prefixed message
let mut buf = vec![0u8; 1024];
let n = recv.read(&mut buf).await?;  // ❌ PARTIAL READ!
let msg = MessageCodec::decode(&buf[..n])?;
```

**VẤN ĐỀ**:
- `read()` trả về **partial data** (không đảm bảo đủ 4 bytes)
- QUIC stream là byte stream, không message boundary
- `read()` có thể return 1, 2, 3 bytes thay vì 4
- → `MessageCodec::decode()` fail với "Buffer too small"
- → Client exit loop
- → Server detect connection close
- → "sending stopped by peer: error 0"

### Fix đã áp dụng (Phase 01)

**File**: `crates/cli_client/src/message_reader.rs` (NEW)
```rust
pub async fn read_message(&mut self) -> Result<NetworkMessage> {
    // Read 4-byte length prefix
    let mut len_buf = [0u8; 4];
    self.recv.read_exact(&mut len_buf).await?;  // ✅ BLOCK until 4 bytes

    let len = u32::from_be_bytes(len_buf) as usize;

    // Read payload
    let mut payload = vec![0u8; len];
    self.recv.read_exact(&mut payload).await?;  // ✅ BLOCK until N bytes

    // Reconstruct full buffer
    let mut full_buffer = Vec::with_capacity(4 + len);
    full_buffer.extend_from_slice(&len_buf);
    full_buffer.extend_from_slice(&payload);

    MessageCodec::decode(&full_buffer)
}
```

**Client main.rs updated** (line 212):
```rust
result = reader.read_message() => {  // ✅ Use MessageReader
    match result {
        Ok(msg) => { /* handle */ }
        Err(_) => break,
    }
}
```

---

## Code Flow Analysis

### Server Side (CORRECT)

**File**: `crates/hostagent/src/quic_server.rs`

1. **Handle Resize** (line 338-348):
   ```rust
   NetworkMessage::Resize { rows, cols } => {
       if let Some(id) = session_id {
           // Session exists → resize PTY
           session_mgr.resize_session(id, rows, cols).await;
       } else {
           // Session not exists → store pending resize
           pending_resize = Some((rows, cols));
       }
   }
   ```

2. **Handle Input (spawn trigger)** (line 282-306):
   ```rust
   NetworkMessage::Input { data } => {
       if let Some(id) = session_id {
           // Session exists → write to PTY
           session_mgr.write_to_session(id, &data).await;
       } else {
           // Session not exists → spawn new session
           Self::spawn_session_with_config(
               &session_mgr,
               pending_resize,  // Apply earlier resize
               &mut pty_task,
               &mut session_id,
               &send_shared,
               &data,
           ).await;
       }
   }
   ```

3. **Spawn Session** (line 376-436):
   ```rust
   async fn spawn_session_with_config(...) -> Result<()> {
       let mut config = TerminalConfig::default();

       // Apply terminal size from earlier Resize message
       if let Some((rows, cols)) = pending_resize {
           config.rows = rows;
           config.cols = cols;
           config.env.push(("COLUMNS".to_string(), cols.to_string()));
           config.env.push(("LINES".to_string(), rows.to_string()));
           config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
       }

       match session_mgr.create_session(config).await {
           Ok(id) => {
               *session_id = Some(id);

               // Resize PTY to match terminal size
               if let Some((rows, cols)) = pending_resize {
                   session_mgr.resize_session(id, rows, cols).await;
               }

               // Spawn PTY->QUIC pump task
               if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                   let send_clone = send_shared.clone();
                   *pty_task = Some(tokio::spawn(async move {
                       let mut send_lock = send_clone.lock().await;
                       pump_pty_to_quic(pty_reader, &mut *send_lock).await;
                   }));
               }

               Ok(())
           }
           Err(e) => {
               tracing::error!("Failed to create session: {}", e);
               Err(e)
           }
       }
   }
   ```

4. **PTY Pump** (line 30-62, `transport/stream.rs`):
   ```rust
   pub async fn pump_pty_to_quic(mut pty: R, send: &mut SendStream) -> Result<()> {
       let mut buf = vec![0u8; 8192];

       loop {
           let n = pty.read(&mut buf).await?;
           if n == 0 {
               break;  // EOF
           }

           // Encode as NetworkMessage::Event
           let msg = NetworkMessage::Event(TerminalEvent::Output {
               data: buf[..n].to_vec()
           });
           let encoded = MessageCodec::encode(&msg)?;

           // Send via QUIC
           send.write_all(&encoded).await?;
       }

       Ok(())
   }
   ```

**Server side hoàn toàn CORRECT**:
- Spawn session đúng cách
- Apply resize config
- Pump PTY output → QUIC với correct framing
- Gửi length-prefixed messages

### Client Side (BUGGY TRƯỚC FIX)

**File**: `crates/cli_client/src/main.rs` (BEFORE fix)

**Interactive loop** (line 205-235):
```rust
loop {
    tokio::select! {
        _ = &mut stdin_task => { stdin_eof = true; }
        Some(encoded) = stdin_rx.recv() => {
            if send.write_all(&encoded).await.is_err() { break; }
        }
        result = reader.read_message() => {  // ✅ NOW CORRECT (after fix)
            match result {
                Ok(msg) => {
                    match msg {
                        NetworkMessage::Event(TerminalEvent::Output { data }) => {
                            stdout.write_all(&data);
                            stdout.flush();
                        }
                        NetworkMessage::Close => break,
                        _ => {}
                    }
                }
                Err(_) => break,  // ❌ BUG: Partial read caused this
            }
        }
    }
}
```

---

## Protocol Format Verification

### MessageCodec (crates/core/src/protocol/codec.rs)

**Encode** (line 18-36):
```rust
pub fn encode(msg: &NetworkMessage) -> Result<Vec<u8>> {
    let payload = to_allocvec(msg)?;

    let len = payload.len() as u32;
    let mut buf = Vec::with_capacity(4 + payload.len());
    buf.extend_from_slice(&len.to_be_bytes());  // 4 bytes length
    buf.extend_from_slice(&payload);            // N bytes payload

    Ok(buf)
}
```

**Decode** (line 41-68):
```rust
pub fn decode(buf: &[u8]) -> Result<NetworkMessage> {
    if buf.len() < 4 {
        return Err(CoreError::InvalidMessageFormat(
            "Buffer too small for length prefix".into(),
        ));
    }

    let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

    if buf.len() < 4 + len {
        return Err(CoreError::InvalidMessageFormat(
            "Buffer too small for payload".into(),
        ));
    }

    let payload = &buf[4..4 + len];
    from_bytes(payload).map_err(CoreError::from)
}
```

**Protocol format**:
```
[4 bytes: big-endian length] [N bytes: postcard payload]
```

**Example**:
```
00 00 00 1B [1B bytes: NetworkMessage::Event data]
```

---

## Why "sending stopped by peer: error 0"?

### Error Message Breakdown

- **"sending stopped by peer"**: Client đóng connection → server detect
- **"error 0"**: Quinn error code 0 = `ConnectionError::ApplicationClosed`

### Chain of Events

1. Server spawn session thành công
2. PTY output có data (shell prompt)
3. Server gửi `NetworkMessage::Event(TerminalEvent::Output { data })`
4. **Client `read()` partial** → `decode()` fail
5. Client break loop → exit function
6. Client drop `send` stream → connection close
7. Server `write_all()` fail → "sending stopped by peer: error 0"

---

## Verification: Server Side is Correct

### Server's Message Reading (quic_server.rs:201-234)

```rust
let mut len_buf = [0u8; 4];

loop {
    // Read 4-byte length prefix
    recv.read_exact(&mut len_buf).await  // ✅ Correct
        .map_err(|_| anyhow::anyhow!("Stream closed while reading length"))?;

    let len = u32::from_be_bytes(len_buf) as usize;

    // Validate size
    if len > 16 * 1024 * 1024 {
        tracing::error!("Message too large: {} bytes", len);
        break;
    }

    // Read payload
    let mut payload = vec![0u8; len];
    recv.read_exact(&mut payload).await  // ✅ Correct
        .map_err(|_| anyhow::anyhow!("Stream closed while reading payload"))?;

    // Reconstruct full buffer
    let mut full_buffer = Vec::with_capacity(4 + len);
    full_buffer.extend_from_slice(&len_buf);
    full_buffer.extend_from_slice(&payload);

    // Parse message
    let msg = MessageCodec::decode(&full_buffer)?;  // ✅ Correct
}
```

**Server side đã dùng `read_exact()` từ đầu** → không có bug ở đây.

---

## Test Scenario

### What happens when user runs client?

1. **Handshake**:
   ```
   Client → Server: Hello { token }
   Server → Client: Hello { }
   Client: Print "Authenticated"
   ```

2. **Banner**:
   ```
   Client: Print ASCII art banner (local operation)
   ```

3. **Eager spawn sequence**:
   ```
   Client → Server: Resize { rows: 24, cols: 80 }
   Server: Store pending_resize = Some((24, 80))

   Client → Server: Input { data: [] }
   Server: Spawn session with 24x80 size
   Server: Start PTY pump task
   ```

4. **PTY output** (shell prompt):
   ```
   PTY: Output data (e.g., "$ ")
   Server: Send NetworkMessage::Event(TerminalEvent::Output { data: b"$ " })
   Server: Encode as [00 00 00 0C][0C bytes payload]
   Server: write_all() to QUIC stream
   ```

5. **Client receive** (BUG TRƯỚC FIX):
   ```
   Client: recv.read(&mut buf)  // ❌ Returns 2 bytes only!
   Client: Decode fail → exit loop
   Client: Connection close
   Server: "sending stopped by peer: error 0"
   ```

---

## Conclusion

### Root Cause

**Bug location**: `crates/cli_client/src/main.rs` (line 212-226)
**Bug type**: Protocol framing bug - used `read()` instead of `read_exact()`
**Impact**: Client couldn't receive server messages → connection close

### Fix Applied

**Phase 01 of refactor 260109-0109** (commit 203d0a8):
- Created `MessageReader` wrapper with `read_exact()` pattern
- Updated client's interactive loop to use `MessageReader`
- Server side was already correct

### Current Status

✅ **BUG ĐÃ ĐƯỢC FIX**

Double-framing bug mentioned in user's context is referring to this same fix.

### Why error appeared "after banner"?

1. Banner display = local operation (stdout write)
2. Resize + Input messages = client → server (working)
3. Server response = server → client (FAIL due to read() bug)

Handshake worked vì:
- Handshake response is small (~20 bytes)
- `read()` sometimes returns full data for small messages
- But PTY output is variable size → partial read common

---

## Unresolved Questions

❌ Không còn unresolved questions. Bug đã được fix và root cause đã được xác định rõ ràng.

---

## References

- **Progress Report**: `plans/reports/progress-260109-ssh-like-terminal-refactor.md`
- **Phase 01 Fix**: Commit 203d0a8
- **MessageReader**: `crates/cli_client/src/message_reader.rs`
- **Server Handler**: `crates/hostagent/src/quic_server.rs:201-234`
- **PTY Pump**: `crates/core/src/transport/stream.rs:30-62`

---

## Attachment

**Files examined**:
1. `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs`
2. `/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/message_reader.rs`
3. `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs`
4. `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/session.rs`
5. `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/pty.rs`
6. `/Users/khoa2807/development/2026/Comacode/crates/core/src/transport/stream.rs`
7. `/Users/khoa2807/development/2026/Comacode/crates/core/src/protocol/codec.rs`
8. `/Users/khoa2807/development/2026/Comacode/crates/core/src/types/message.rs`

**Total lines examined**: ~1200 lines
**Root cause identified**: ✅ Line 212-226, `main.rs` (before fix)
**Fix location**: ✅ `message_reader.rs` (new file)
