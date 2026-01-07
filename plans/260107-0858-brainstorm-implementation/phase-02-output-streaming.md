---
title: "Phase 02: Output Streaming Refactor"
description: "Channel-based architecture (mpsc::channel) with natural backpressure"
status: completed
priority: P0
effort: 6h
phase: 02
created: 2026-01-07
completed: 2026-01-07
---

## Objectives

Refactor output forwarding từ shared state sang channel-based architecture để eliminate race conditions và create natural backpressure.

## Current Architecture (Problematic)

```
PTY Output → Arc<Mutex<Vec<u8>>> → Network Writer
             ↑
             Race condition khi read/write concurrently
```

## Target Architecture (Channel-based)

```
PTY Reader Task  →  mpsc::channel(1024)  →  Network Writer Task
                     (bounded buffer)
                              ↓
                        Natural backpressure
```

## Tasks

### 2.1 Add Channel & Bytes Dependencies (15min)

**File**: `crates/hostagent/Cargo.toml`, `crates/core/Cargo.toml`

```toml
[dependencies]
tokio = { workspace = true, features = ["sync"] }
bytes = "1.8"  # Zero-copy bytes, shared buffers
```

### 2.2 Create Output Stream Module (1h)

**File**: `crates/core/src/streaming.rs` (new)

```rust
use bytes::Bytes;
use tokio::sync::mpsc;

/// Bounded channel for terminal output streaming
/// Dùng Bytes thay Vec<u8> cho zero-copy clone
pub struct OutputStream {
    tx: mpsc::Sender<Bytes>,
}

impl OutputStream {
    /// Create new stream with 1024 buffer capacity
    pub fn new(capacity: usize) -> (Self, mpsc::Receiver<Bytes>) {
        let (tx, rx) = mpsc::channel(capacity);
        (Self { tx }, rx)
    }

    /// Send PTY output (returns error if buffer full = backpressure)
    pub async fn send(&self, data: Bytes) -> Result<(), mpsc::error::SendError<Bytes>> {
        self.tx.send(data).await
    }

    /// Try send without waiting (for non-blocking contexts)
    pub fn try_send(&self, data: Bytes) -> Result<(), mpsc::error::TrySendError<Bytes>> {
        self.tx.try_send(data)
    }
}
```

### 2.3 Refactor HostAgent PTY Loop (2h)

**File**: `crates/hostagent/src/session.rs` (assume exists)

**Before** (pseudo-code):
```rust
let output_buffer = Arc::new(Mutex::new(Vec::new()));

// Reader task
task::spawn(async move {
    loop {
        let data = pty.read().await?;
        output_buffer.lock().await.push(data);
    }
});

// Writer task
task::spawn(async move {
    loop {
        let data = output_buffer.lock().await.drain(..).collect();
        stream.write_all(&data).await?;
    }
});
```

**After**:
```rust
use bytes::Bytes;
use comacode_core::streaming::OutputStream;

let (output_stream, mut rx) = OutputStream::new(1024);

// Reader task: PTY → Channel
// QUAN TRỌNG: portable-pty.read() là blocking I/O, cần spawn_blocking
let pty_clone = pty.clone(); // Clone reader handle
let tx_clone = output_stream.tx.clone();

let pty_reader = tokio::task::spawn_blocking(move || {
    let mut reader = pty_clone.reader;
    let mut buf = [0u8; 8192];

    loop {
        // Blocking read - sẽ chặn thread này nhưng không chặn Tokio runtime
        match reader.read(&mut buf) {
            Ok(0) => break,  // EOF
            Ok(n) => {
                // Zero-cost convert sang Bytes
                let data = Bytes::copy_from_slice(&buf[..n]);

                // Blocking send OK vì đang ở trong spawn_blocking
                if tx_clone.blocking_send(data).is_err() {
                    tracing::warn!("Output stream closed");
                    break;
                }
            }
            Err(e) => {
                tracing::error!("PTY read error: {}", e);
                break;
            }
        }
    }
    Ok::<(), anyhow::Error>(())
});

// Writer task: Channel → QUIC Stream (async task)
let net_writer = tokio::spawn(async move {
    while let Some(data) = rx.recv().await {
        stream.write_all(&data).await?;
    }
    Ok::<_, anyhow::Error>(())
});

tokio::select! {
    _ = pty_reader => {},
    _ = net_writer => {},
}
```

### 2.4 Add Backpressure Monitoring (30min)

**File**: `crates/hostagent/src/session.rs`

```rust
impl OutputStream {
    /// Get current buffer capacity (for monitoring)
    pub fn capacity(&self) -> usize {
        self.tx.capacity()
    }

    /// Get approximate remaining slots
    pub fn remaining(&self) -> usize {
        self.tx.semaphore().available_permits()
    }

    /// Get sender for cloning (needed for spawn_blocking)
    pub fn sender(&self) -> mpsc::Sender<Bytes> {
        self.tx.clone()
    }
}
```

**Logging**:
```rust
// Log backpressure events
if output_stream.remaining() < 100 {
    tracing::warn!("Output buffer near capacity: {}/1024", output_stream.remaining());
}
```

### 2.5 Update Mobile Bridge (1.5h)

**File**: `crates/mobile_bridge/src/bridge.rs`

Similar refactor cho Flutter → Rust output forwarding.

**Key changes**:
1. Replace `Arc<Mutex<Vec<u8>>>` with `OutputStream`
2. Create dedicated reader task for QUIC stream
3. Send data to Flutter UI via channel

### 2.6 Snapshot Buffer Integration (1h)

**File**: `crates/hostagent/src/snapshot.rs` (new)

```rust
use std::collections::VecDeque;

/// Ring buffer cho terminal output snapshot
/// QUAN TRỌNG: Lưu raw bytes (VecDeque<u8>) thay vì String lines
/// để tránh làm gãy ANSI codes (colors, cursor movement, etc.)
pub struct SnapshotBuffer {
    buffer: VecDeque<u8>,
    max_bytes: usize,  // Ví dụ: 1MB (đủ cho vài trăm màn hình)
}

impl SnapshotBuffer {
    pub fn new(max_bytes: usize) -> Self {
        Self {
            buffer: VecDeque::with_capacity(max_bytes),
            max_bytes,
        }
    }

    /// Push raw PTY output vào buffer
    pub fn push(&mut self, data: &[u8]) {
        for &byte in data {
            if self.buffer.len() >= self.max_bytes {
                self.buffer.pop_front();  // Remove oldest byte
            }
            self.buffer.push_back(byte);
        }
    }

    /// Get full snapshot for resync (raw bytes)
    pub fn get_snapshot(&self) -> Vec<u8> {
        self.buffer.iter().cloned().collect()
    }

    /// Get current buffer size
    pub fn len(&self) -> usize {
        self.buffer.len()
    }
}
```

**Integration**:
```rust
use bytes::Bytes;

let mut snapshot_buf = SnapshotBuffer::new(1_048_576); // 1MB
let output_stream = OutputStream::new(1024);
let tx_snapshot = output_stream.sender(); // Clone sender cho snapshot

// Trong reader task (spawn_blocking)
loop {
    match reader.read(&mut buf) {
        Ok(0) => break,
        Ok(n) => {
            let data = Bytes::copy_from_slice(&buf[..n]);

            // Clone rất rẻ (Bytes chỉ tăng ref count)
            snapshot_buf.push(&data);

            // Gửi đi
            if tx_snapshot.blocking_send(data).is_err() {
                break;
            }
        }
        Err(e) => break,
    }
}
```

**Why Raw Bytes?**
- Terminal output chứa ANSI codes (colors, cursor movement)
- Parse thành String → .lines() sẽ phá vỡ ANSI structure
- Client nhận raw bytes → xterm.dart tự xử lý ANSI
- Reconnect sẽ hiển thị đúng vim/htop UI thay vì rác text

## Testing Strategy

**Unit Tests**:
```rust
#[tokio::test]
async fn test_backpressure() {
    let (stream, mut rx) = OutputStream::new(4);  // Small buffer

    // Fill buffer
    for _ in 0..4 {
        stream.send(vec![1]).await.unwrap();
    }

    // Next send should block or fail
    let result = stream.try_send(vec![2]);
    assert!(result.is_err());
}
```

**Load Test**:
- Run `yes` command (rapid output)
- Monitor buffer capacity via logs
- Verify PTY eventually blocks on write

**Acceptance Criteria**:
- ✅ Channel-based streaming replaces shared state
- ✅ Backpressure logs visible during high output
- ✅ No race conditions in concurrent access
- ✅ Snapshot buffer captures 1000 lines

## Dependencies

- Phase 01 (SnapshotBuffer needs SNAPSHOT_BUFFER_LINES constant)

## Blocked By

- None

## Performance Notes

**Channel Capacity Tuning**:
- 1024 messages × 8KB avg = 8MB buffer
- Too small → frequent backpressure
- Too large → memory bloat
- Monitor in production, adjust if needed

**Zero-Copy Optimization** (Future):
- Consider `bytes::Bytes` cho shared buffers
- Avoid Vec allocations in hot path
- Profile first before optimizing

## Resolved Decisions

Buffer size: 1024 messages (default). Will monitor in Phase 05 load testing.

Snapshot granularity: Byte-based (Raw) decided. Line-based logic discarded due to ANSI corruption risk.

PTY blocking: Confirmed portable-pty read is blocking. Using spawn_blocking to handle it safely.
