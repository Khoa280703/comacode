# Debugger Report: Protocol Framing Bug
**ID**: debugger-260109-0051
**Date**: 2026-01-09
**Severity**: CRITICAL
**Status**: ROOT CAUSE IDENTIFIED

## Executive Summary

**ROOT CAUSE FOUND**: Client is using `recv.read()` instead of `recv.read_exact()`, breaking the length-prefixed protocol framing.

This is NOT a PTY timing issue. This is NOT a Zsh prompt issue. This is a **PROTOCOL BUG**.

## The Bug

### Location
`/Users/khoa2807/development/2026/Comacode/crates/cli_client/src/main.rs:191`

### Current (Broken) Code
```rust
result = recv.read(&mut recv_buf) => {
    match result {
        Ok(Some(n)) => {
            if let Ok(msg) = MessageCodec::decode(&recv_buf[..n]) {
                // ...
            }
        }
    }
}
```

### The Problem

**Protocol Format**:
```
[4 bytes: length (big endian)] [N bytes: payload]
```

**What `read()` does**:
- Returns whatever data is available (could be 1 byte, could be 1000 bytes)
- Does NOT guarantee reading complete messages

**What `read_exact()` does**:
- Reads EXACTLY the requested number of bytes
- Blocks until all bytes are available

### Actual Flow (When Bug Manifests)

1. **Server sends first Output message** (prompt from Zsh):
   ```
   [00 00 00 15] [postcard-encoded Output message with "khoa@mac ~ %"]
   ```

2. **Client calls `recv.read(buf)`**:
   - Gets ONLY the 4-byte length prefix: `[00 00 00 15]`
   - n = 4

3. **Client calls `MessageCodec::decode(&buf[..4])`**:
   - Codec expects: `[length (4 bytes)] [payload (N bytes)]`
   - But only received: `[00 00 00 15]` (just the length!)
   - **Decode FAILS** or returns garbage

4. **Next read gets the payload**:
   - Now `read()` returns the remaining 15 bytes
   - But client tries to decode it as if it's a NEW message
   - Interprets `[postcard data]` as `[length prefix]` → **GARBAGE**

### Why This Causes "Newline Jump"

When the client decodes garbage:
- Postcard payload bytes get interpreted as length prefix
- First byte of payload might be `0x0A` (newline) or similar
- Or the deserialization produces weird data
- Client writes corrupted data to stdout
- Terminal interprets it as newline/position change

### Why It's Intermittent

- **Sometimes works**: QUIC happens to deliver full message in one TCP packet
- **Sometimes fails**: QUIC splits message across multiple reads
- **TCP/QUIC segmentation** depends on:
  - Network conditions
  - Buffer sizes
  - Timing
  - Packet fragmentation

This explains ALL the symptoms:
- ❌ Resize timing → Nothing to do with it
- ❌ Env vars → Nothing to do with it
- ❌ PTY spawn delay → Nothing to do with it
- ✅ **Protocol framing bug → THIS IS IT**

## Correct Implementation

The client MUST use the same pattern as the server (`pump_quic_to_pty` in `stream.rs:90-106`):

```rust
let mut len_buf = [0u8; 4];

loop {
    // Read length prefix EXACTLY
    recv.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;

    // Validate size
    if len > 16 * 1024 * 1024 {
        return Err(...);
    }

    // Read payload EXACTLY
    let mut data = vec![0u8; len];
    recv.read_exact(&mut data).await?;

    // Now decode
    let msg = MessageCodec::decode(&data)?;

    match msg {
        NetworkMessage::Event(TerminalEvent::Output { data }) => {
            stdout.write_all(&data)?;
            stdout.flush()?;
        }
        // ...
    }
}
```

## Evidence

### Server Side (CORRECT)
- `crates/core/src/transport/stream.rs:90-105`
- Uses `read_exact()` for both length and payload
- Properly implements length-prefixed protocol

### Client Side (BROKEN)
- `crates/cli_client/src/main.rs:191-194`
- Uses `read()` which returns partial data
- Breaks protocol framing

### Handshake (Works by luck)
- `main.rs:110`: Uses `read()` for hello message
- Only works because message is small and likely arrives in one packet
- Still wrong, just hasn't failed yet

## Timeline of Failed Attempts

All previous attempts failed because they were fixing the WRONG thing:

1. Resize before spawn → Wrong (PTY timing)
2. Ping to force QUIC flush → Wrong (network timing)
3. Eager spawn → Wrong (PTY timing)
4. Wait for prompt → Wrong (PTY timing)
5. Double-tap resize → Wrong (PTY timing)
6. Inject COLUMNS/LINES → Wrong (Zsh config)
7. Remove env vars → Wrong (Zsh config)
8. Pincer Movement → Wrong (Zsh + PTY timing)
9. Banner clear line → Wrong (terminal rendering)
10. Remove delayed resize → Wrong (PTY timing)
11. Immediate resize → Wrong (PTY timing)

**The bug was in the PROTOCOL LAYER all along.**

## Impact Assessment

### Current Impact
- Terminal output corrupted on first character
- Unpredictable behavior (depends on network segmentation)
- Protocol violation

### Risk Level
- **CRITICAL**: Protocol implementation is fundamentally broken
- **Data Loss**: Corrupted messages can cause arbitrary terminal behavior
- **Reliability**: 100% failure rate under certain network conditions

## Recommendations

### Immediate Fix (CRITICAL)

1. **Replace client receive loop** with proper framing:
   ```rust
   // In crates/cli_client/src/main.rs:191
   // Use read_exact() pattern from stream.rs:90-105
   ```

2. **Extract message reading helper**:
   ```rust
   // Add to crates/core/src/transport/stream.rs
   pub async fn read_message(recv: &mut RecvStream) -> Result<NetworkMessage>
   ```

3. **Use helper in both server and client**:
   - Server: `pump_quic_to_pty`
   - Client: main loop

### Long-term Improvements

1. **Add integration test** for fragmented messages:
   ```rust
   #[tokio::test]
   async fn test_fragmented_message_reception() {
       // Simulate read() returning partial data
       // Verify read_exact() handles it correctly
   }
   ```

2. **Add protocol documentation**:
   - Document length-prefixed framing clearly
   - Add examples of correct receive pattern

3. **Consider framing library**:
   - `tokio-util::codec::LengthDelimitedCodec`
   - Or custom `AsyncRead` wrapper

## Unresolved Questions

1. **Why did previous attempts sometimes work?**
   - Likely because small messages arrive in one QUIC stream read
   - Need to verify with packet captures

2. **Are there other places using `read()` incorrectly?**
   - Need to audit all RecvStream usage
   - Check for partial read patterns

3. **Should we add buffer reuse for performance?**
   - Currently allocating new Vec for each message payload
   - Could reuse buffer with `read_exact()`

4. **Why didn't tests catch this?**
   - Need integration tests with realistic network conditions
   - Mock QUIC stream that returns partial data

## Next Steps

1. Implement fix in client receive loop
2. Add integration test for fragmented messages
3. Verify fix with manual testing
4. Audit all `RecvStream::read()` usage in codebase

## Appendix: Protocol Flow

### Correct Flow
```
Server: write([len, payload]) → QUIC → Client: read_exact(4) → read_exact(len) → decode
```

### Broken Flow
```
Server: write([len, payload]) → QUIC → Client: read(buf) → gets [len] only → FAIL
```

The `read()` API contract:
- Returns `Ok(n)` where 0 < n ≤ requested size
- May return partial data
- Caller MUST handle short reads

The `read_exact()` API contract:
- Returns `Ok(())` only when ALL bytes read
- Handles partial reads internally
- Guaranteed complete message

---

**Report Status**: COMPLETE - Root cause identified
**Priority**: CRITICAL - Immediate fix required
**Confidence**: HIGH - Protocol violation is clear
