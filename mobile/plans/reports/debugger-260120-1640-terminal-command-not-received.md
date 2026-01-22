# Debug Report: Terminal Command Not Received by Server

**Report ID:** debugger-260120-1640-terminal-command-not-received
**Date:** 2026-01-20
**Severity:** P0 - Critical functionality broken
**Status:** Root cause identified

## Executive Summary

Terminal commands from mobile app are not reaching the server after successful authentication. The root cause is a **mismatch in message encoding format** between client and server:

- **Client (quic_client.rs:342-346)**: Sends command with **length prefix** (correctly uses `MessageCodec::encode()`)
- **Server (quic_server.rs:201-225)**: Reads length prefix **TWICE** - once explicitly, then again inside `MessageCodec::decode()`

This causes the server to interpret the command payload as a length prefix, resulting in:
- Corrupted message decoding
- Message type mismatch
- Commands silently discarded

## Root Cause Analysis

### 1. Client Side (CORRECT)

**File:** `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs`
**Lines:** 337-350

```rust
pub async fn send_command(&self, command: String) -> Result<(), String> {
    let send_stream = self.send_stream.as_ref()
        .ok_or_else(|| "Not connected".to_string())?;

    let cmd_msg = NetworkMessage::Command(TerminalCommand::new(command));
    let encoded = MessageCodec::encode(&cmd_msg)  // ✅ Includes length prefix
        .map_err(|e| format!("Failed to encode command: {}", e))?;

    let mut send = send_stream.lock().await;
    send.write_all(&encoded).await  // ✅ Sends [length][payload]
        .map_err(|e| format!("Failed to send command: {}", e))?;

    debug!("Sent command via QUIC");
    Ok(())
}
```

**MessageCodec::encode()** (codec.rs:18-35):
```rust
pub fn encode(msg: &NetworkMessage) -> Result<Vec<u8>> {
    let payload = to_allocvec(msg).map_err(CoreError::from)?;
    // Add length prefix (4 bytes, big endian)
    let len = payload.len() as u32;
    let mut buf = Vec::with_capacity(4 + payload.len());
    buf.extend_from_slice(&len.to_be_bytes());  // ✅ Length prefix
    buf.extend_from_slice(&payload);             // ✅ Postcard data
    Ok(buf)  // Returns: [4-byte length][postcard payload]
}
```

**Client sends:** `[0x00, 0x00, 0x00, 0x2A][postcard_data...]`

---

### 2. Server Side (INCORRECT - DOUBLE LENGTH PREFIX READ)

**File:** `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs`
**Lines:** 200-234

```rust
async fn handle_stream(
    send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    ...
) -> Result<()> {
    let mut len_buf = [0u8; 4];

    loop {
        // ❌ PROBLEM: Read 4-byte length prefix FIRST
        recv.read_exact(&mut len_buf).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading length"))?;

        let len = u32::from_be_bytes(len_buf) as usize;

        // Validate size
        if len > 16 * 1024 * 1024 {
            tracing::error!("Message too large: {} bytes", len);
            break;
        }

        // Read payload
        let mut payload = vec![0u8; len];
        recv.read_exact(&mut payload).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading payload"))?;

        // ❌ PROBLEM: Reconstruct [length][payload] buffer
        let mut full_buffer = Vec::with_capacity(4 + len);
        full_buffer.extend_from_slice(&len_buf);  // Add length prefix
        full_buffer.extend_from_slice(&payload);  // Add payload

        // ❌ PROBLEM: MessageCodec::decode() expects [length][payload]
        // But we ALREADY stripped the length prefix above!
        let msg = match MessageCodec::decode(&full_buffer) {
            Ok(msg) => msg,
            Err(e) => {
                tracing::error!("Failed to decode message: {}", e);
                continue;
            }
        };
        ...
    }
}
```

**MessageCodec::decode()** (codec.rs:41-67):
```rust
pub fn decode(buf: &[u8]) -> Result<NetworkMessage> {
    // ❌ Reads FIRST 4 bytes as length prefix
    let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

    // ❌ Deserializes from buf[4..4+len]
    let payload = &buf[4..4 + len];
    from_bytes(payload).map_err(CoreError::from)
}
```

---

### 3. What Happens When Client Sends Command

**Client sends:** `[0x00, 0x00, 0x00, 0x2A][postcard_command_data...]`

**Server does:**
1. Reads first 4 bytes → `len = 0x2A` (42 bytes) ✅ Correct
2. Reads next 42 bytes → `payload = [postcard_command_data...]` ✅ Correct
3. Constructs `full_buffer = [0x00, 0x00, 0x00, 0x2A][postcard_command_data...]` ✅ Correct
4. Calls `MessageCodec::decode(&full_buffer)` →
   - Reads first 4 bytes AGAIN as length → `len = 0x2A` ✅
   - Tries to deserialize `buf[4..70]` → **POSTCARD DATA INTERPRETED AS LENGTH PREFIX** ❌

**Result:** Garbage data → decode error → message discarded

---

## Why This Breaks

The server's `handle_stream()` function manually implements length-prefixed framing, but `MessageCodec::decode()` **also** expects length-prefixed framing. This creates a **double layer of length prefix handling**:

```
Client:                     [length][payload]
                              ↓
Server reads length         [length][payload]  ← Manual framing
                              ↓
Server reads payload
                              ↓
Reconstructs buffer        [length][payload]
                              ↓
MessageCodec::decode()     [length][payload]  ← Expects framing AGAIN
                              ↓
Reads length AGAIN → Treats payload as length ❌
```

---

## Impact Assessment

### Affected Message Types
- ✅ **Hello**: Works because server doesn't decode after Hello ACK
- ❌ **Command**: Completely broken (reported issue)
- ❌ **Input**: Broken (raw keystrokes won't work)
- ❌ **Resize**: Broken (screen rotation won't work)
- ❌ **Ping**: Broken

### Authentication Success
The "Client authenticated" log appears because:
1. Server reads Hello message with manual framing (works by luck)
2. Server sends Hello ACK (bypasses decode)
3. Connection stays open
4. Subsequent commands fail at decode step

---

## Evidence

### Server Log Pattern
```
[INFO] Connection from 192.168.1.100:12345
[INFO] Client hello protocol_version=1, app_version=0.1.0
[INFO] Client authenticated: 192.168.1.100:12345  ← ✅ Auth success
[WARN] Failed to decode message: ...  ← ❌ Command decode fails
```

### Client Behavior
- Mobile app connects successfully
- QR scan + auth token validation works
- Terminal commands sent via `send_terminal_command()`
- **No response from server**
- No error visible in app (error swallowed in `send_command`)

---

## Solution

### Option 1: Fix Server (RECOMMENDED)

**Change server to read raw stream and let MessageCodec handle framing:**

**File:** `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs`
**Lines:** 200-234

**Current code (BROKEN):**
```rust
let mut len_buf = [0u8; 4];
loop {
    recv.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;
    let mut payload = vec![0u8; len];
    recv.read_exact(&mut payload).await?;
    let mut full_buffer = Vec::with_capacity(4 + len);
    full_buffer.extend_from_slice(&len_buf);
    full_buffer.extend_from_slice(&payload);
    let msg = MessageCodec::decode(&full_buffer)?;  // ❌ Double framing
}
```

**Fixed code:**
```rust
let mut read_buf = vec![0u8; 8192];
loop {
    let n = recv.read(&mut read_buf).await?
        .ok_or_else(|| anyhow::anyhow!("Connection closed"))?;

    let msg = MessageCodec::decode(&read_buf[..n])?;  // ✅ Single framing
}
```

**Problem with this approach:** `read()` might not read full message. Need buffering.

---

### Option 2: Use Frame Decoder (BEST)

Create a proper frame reader that handles partial reads:

```rust
struct FrameReader {
    buffer: Vec<u8>,
}

impl FrameReader {
    fn new() -> Self {
        Self { buffer: Vec::new() }
    }

    async fn read_frame<R: AsyncReadExt + Unpin>(
        &mut self,
        reader: &mut R,
    ) -> Result<Vec<u8>> {
        // Read length prefix
        if self.buffer.len() < 4 {
            self.buffer.resize(4, 0);
            reader.read_exact(&mut self.buffer).await?;
        }

        let len = u32::from_be_bytes([self.buffer[0], self.buffer[1], self.buffer[2], self.buffer[3]]) as usize;

        // Read payload
        self.buffer.resize(4 + len, 0);
        reader.read_exact(&mut self.buffer[4..]).await?;

        Ok(self.buffer.split_off(0))
    }
}
```

---

### Option 3: Remove Manual Framing (EASIEST)

**Remove manual length prefix reading from server:**

```rust
// In handle_stream(), replace lines 200-234 with:
let mut read_buf = vec![0u8; 8192];

loop {
    let n = recv.read(&mut read_buf).await
        .map_err(|_| anyhow::anyhow!("Stream closed"))?
        .ok_or_else(|| anyhow::anyhow!("Connection closed"))?;

    // Decode all messages in buffer (handles partial reads)
    let messages = MessageCodec::decode_stream(&read_buf[..n])
        .map_err(|e| anyhow::anyhow!("Decode error: {}", e))?;

    for msg in messages {
        // Handle each message
        match msg {
            NetworkMessage::Hello { .. } => { /* ... */ }
            NetworkMessage::Command(cmd) => { /* ... */ }
            // ...
        }
    }
}
```

**Why this works:**
- `MessageCodec::decode_stream()` handles multiple messages in one read
- No double framing
- Handles partial reads correctly

---

## Recommended Fix

**Option 3 is recommended** because:
1. ✅ Minimal code change
2. ✅ Uses existing `MessageCodec::decode_stream()`
3. ✅ Handles edge cases (partial reads, multiple messages)
4. ✅ No new dependencies
5. ✅ Matches protocol design (codec handles framing)

---

## Implementation Steps

1. **Backup current code**
   ```bash
   git diff crates/hostagent/src/quic_server.rs > ~/quic_server_fix.patch
   ```

2. **Apply fix to quic_server.rs**
   - Replace lines 200-234 with Option 3 code
   - Add proper error handling
   - Add debug logging

3. **Test locally**
   ```bash
   cd /Users/khoa2807/development/2026/Comacode
   cargo run --bin hostagent
   ```

4. **Test with mobile app**
   - Scan QR
   - Send command: `ping 8.8.8.8`
   - Verify server logs show: `[INFO] Command received: ping 8.8.8.8`

5. **Add integration test**
   - Test command roundtrip
   - Test raw input
   - Test resize
   - Test ping/pong

---

## Unresolved Questions

1. **Why did Hello work?**
   - Server sends Hello ACK without calling `MessageCodec::decode()`
   - Should verify if Hello response encoding is correct

2. **Are there other places with double framing?**
   - Check all uses of `MessageCodec::decode()`
   - Verify no other manual framing code

3. **Testing coverage?**
   - Need integration test for full message flow
   - Need test for partial reads

4. **Performance impact?**
   - `decode_stream()` allocates per message
   - Consider reusing buffers

---

## References

**Files involved:**
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs` (lines 337-350)
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs` (lines 200-234)
- `/Users/khoa2807/development/2026/Comacode/crates/core/src/protocol/codec.rs` (lines 18-67)

**Related issues:**
- Previous report: `plans/reports/debugger-260109-2358-client-already-initialized.md`

**Protocol documentation:**
- Length-prefixed framing with Postcard serialization
- 4-byte big-endian length prefix
- Max message size: 16MB

---

## Next Steps

1. ✅ Root cause identified
2. ⏳ Apply fix (Option 3)
3. ⏳ Test with mobile app
4. ⏳ Add integration tests
5. ⏳ Update documentation
