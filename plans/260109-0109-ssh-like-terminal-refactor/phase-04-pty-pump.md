# Phase 04: PTY Pump Refactor

**Priority**: P1 (High)
**Effort**: 4h
**Status**: Pending

## Overview

Fix PTY output pumping architecture. Current implementation treats each `read()` as separate message, chopping terminal output into fragments.

**[CRITICAL UPDATE]**: 50ms timeout is TOO SLOW for interactive typing. User types 'a', 50ms later it appears → feels laggy.

**Solution**: Smart Flush with low latency priority:
- Small reads (typing) → SEND IMMEDIATELY
- Large reads (cat, ls -R) → batch efficiently

## Context Links

- [Scout: Transport Analysis](../scout/scout-transport-report.md)
- [Research: PTY Output Analysis](../research/pty-output-research.md)

## Requirements

1. PTY output sent as continuous byte stream
2. Proper message boundaries preserved
3. No chopped terminal fragments
4. Multi-consumer support (future-proof)

## Root Cause Analysis

**Current Flow (BROKEN)**:
```
PTY output (8KB) → Channel as Bytes → StreamReader.read() (may return 1KB)
  → NetworkMessage::Event { data: 1KB }
PTY output (next 8KB) → ...
  → NetworkMessage::Event { data: 8KB }
```

**Problem**: Client receives fragmented messages, terminal rendering broken.

**Correct Flow (SSH-like)**:
```
PTY output → Collect until buffer full or timeout
  → Single NetworkMessage::Event { data: all bytes }
Or: Use dedicated stream without message boundaries
```

## Architecture Options

### Option A: Batched Messages (RECOMMENDED)

Send terminal output in batches (e.g., 8KB or 50ms timeout).

**Pros**:
- Simple to implement
- Maintains message protocol
- Compatible with current architecture

**Cons**:
- Slight latency (50ms max)
- Not true stream semantics

### Option B: Dedicated Stream (SSH-like)

Use separate QUIC stream for raw terminal data without NetworkMessage wrapper.

**Pros**:
- True stream semantics
- Zero additional latency
- Most like SSH

**Cons**:
- Requires protocol change
- More complex connection management
- Need stream coordination

## Implementation Steps (Option A - Smart Flush)

### Step 1: Add Smart Buffer Accumulation to pump_pty_to_quic

**File**: `crates/core/src/transport/stream.rs`

**Before**:
```rust
pub async fn pump_pty_to_quic<R>(mut pty: R, send: &mut SendStream) -> Result<()>
where R: AsyncReadExt + Unpin + Send
{
    let mut buf = vec![0u8; 8192];

    loop {
        let n = pty.read(&mut buf).await?;
        if n == 0 { break; }

        // IMMEDIATE send - WRONG!
        let msg = NetworkMessage::Event(TerminalEvent::Output {
            data: buf[..n].to_vec()
        });
        let encoded = MessageCodec::encode(&msg)?;
        send.write_all(&encoded).await?;
    }
}
```

**After (Smart Flush)**:
```rust
use std::time::Duration;

pub async fn pump_pty_to_quic<R>(mut pty: R, send: &mut SendStream) -> Result<()>
where R: AsyncReadExt + Unpin + Send
{
    let mut read_buf = vec![0u8; 8192];

    // Smart flush constants:
    // - SMALL_READ_THRESHOLD: Below this, send immediately (typing)
    // - LARGE_READ_THRESHOLD: Above this, batch more (bulk output)
    // - MAX_LATENCY: Maximum time to hold data (5ms = imperceptible)
    const SMALL_READ_THRESHOLD: usize = 256;  // ~1-2 keystrokes
    const LARGE_READ_THRESHOLD: usize = 4096; // 4KB
    const MAX_LATENCY: Duration = Duration::from_millis(5);

    let mut output_buffer = Vec::new();
    let mut last_send = std::time::Instant::now();

    loop {
        let n = pty.read(&mut read_buf).await?;
        if n == 0 {
            // EOF - send remaining buffer
            if !output_buffer.is_empty() {
                send_output(&output_buffer, send).await?;
            }
            break;
        }

        output_buffer.extend_from_slice(&read_buf[..n]);

        // SMART FLUSH LOGIC:
        // 1. Small read (typing) → Send immediately for low latency
        // 2. Large read (bulk) → Batch efficiently
        // 3. Timeout reached → Flush anyway

        let should_send_immediate = n <= SMALL_READ_THRESHOLD && output_buffer.len() <= SMALL_READ_THRESHOLD * 2;
        let should_send_batch = output_buffer.len() >= LARGE_READ_THRESHOLD;
        let should_send_timeout = last_send.elapsed() >= MAX_LATENCY;

        if should_send_immediate || should_send_batch || should_send_timeout {
            send_output(&output_buffer, send).await?;
            output_buffer.clear();
            last_send = std::time::Instant::now();
        }
    }

    Ok(())
}

async fn send_output(data: &[u8], send: &mut SendStream) -> Result<()> {
    let msg = NetworkMessage::Event(TerminalEvent::Output {
        data: data.to_vec(),
    });
    let encoded = MessageCodec::encode(&msg)?;
    send.write_all(&encoded).await?;
    Ok(())
}
```

**Key Changes**:
- **5ms timeout** (not 50ms) - imperceptible to humans
- **Immediate send for small reads** - typing feels instant
- **Batch for large reads** - efficient for bulk output

### Step 2: Fix get_pty_reader to not remove receiver

**File**: `crates/hostagent/src/session.rs`

**Before**:
```rust
pub async fn get_pty_reader(&self, session_id: u64) -> Option<impl AsyncReadExt + Unpin + Send> {
    let mut outputs = self.outputs.lock().await;
    let rx = outputs.remove(&session_id)?;  // REMOVES!
    let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
    Some(StreamReader::new(stream))
}
```

**After**:
```rust
pub async fn get_pty_reader(&self, session_id: u64) -> Option<impl AsyncReadExt + Unpin + Send> {
    let outputs = self.outputs.lock().await;
    let rx = outputs.get(&session_id)?.clone();  // Clone receiver!
    let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
    drop(outputs);  // Release lock before creating stream
    Some(StreamReader::new(stream))
}
```

**Note**: This requires changing Receiver to cloneable type (use broadcast or watch channel).

### Step 3: Update Cleanup Logic

**File**: `crates/hostagent/src/quic_server.rs`

Ensure cleanup removes receiver after session ends:
```rust
// Cleanup session on disconnect
if let Some(id) = session_id {
    let _ = session_mgr.cleanup_session(id).await;  // This removes receiver
}
```

## Related Code Files

### Modify
- `crates/core/src/transport/stream.rs` - pump_pty_to_quic function
- `crates/hostagent/src/session.rs` - get_pty_reader function
- `crates/hostagent/src/pty.rs` - Consider channel type changes

## Todo List

- [ ] Implement buffer accumulation in pump_pty_to_quic
- [ ] Add batch size and timeout constants
- [ ] Fix get_pty_reader to clone receiver
- [ ] Update cleanup to properly remove receiver
- [ ] Test terminal output displays correctly
- [ ] Verify no chopped fragments
- [ ] Measure typing latency (should be <10ms)

## Success Criteria

1. Terminal prompt displays correctly on first connect
2. No chopped output fragments
3. **Typing latency <10ms** (feels instant) - not 50ms!
4. Bulk output (cat large file) still efficient
5. Backpressure handled correctly

## Risk Assessment

**Risk**: Buffer batching increases latency
**Mitigation**: 5ms timeout + immediate send for small reads = imperceptible

**Risk**: Memory usage with buffering
**Mitigation**: 4KB batch limit prevents unbounded growth

**Risk**: Smart flush logic complexity
**Mitigation**: Simple threshold-based logic, easy to test

**Risk**: Channel clone complexity
**Mitigation**: Test thoroughly, consider watch channel as alternative

## Future Considerations

- **Option B** (dedicated stream) for true SSH-like behavior
- **Multi-consumer** support for logs/monitoring
- **Compression** for high-bandwidth output
