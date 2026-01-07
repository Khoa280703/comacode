# Brainstorming: Phase 05 Network Protocol - Technical Review

**Date**: 2026-01-07
**Topic**: Review & Revise Phase 05 Plan - Network Protocol
**Conclusion**: **Plan hiện tại OVER-ENGINEERED - Cần revise**

---

## User's Technical Feedback (CRITICAL)

### 1. ⚠️ Flow Control - Don't Reinvent Quinn

**Plan Problem:**
```rust
// Step 3 của plan cũ - TỰ CODE flow control
pub struct FlowController {
    window_size: u64,
    pending_bytes: usize,
    max_pending: usize,
}
```

**Reality:** Quinn đã có sẵn flow control (connection + stream level)
- Automatic window updates
- BBR/Cubic congestion control
- Built-in backpressure

**Risk:** "Double Buffering" → Deadlock hoặc ảo Head-of-Line Blocking

**Revised Approach:**
```rust
// Application-level backpressure
pub async fn pump_pty_to_network(
    mut pty_reader: Box<dyn Read + Send>,
    mut quic_sender: quinn::SendStream
) -> Result<()> {
    let mut buf = [0u8; 4096];
    loop {
        let n = pty_reader.read(&mut buf)?;
        if n == 0 { break; }

        // Quinn's write_all tự await khi network chậm
        // → Vòng lặp dừng → ngừng đọc PTY → Backpressure chuẩn!
        quic_sender.write_all(&buf[..n]).await?;
    }
    Ok(())
}
```

---

### 2. Connection Migration ≠ Reconnect

**Plan Problem:** Step 5 gọi là "Migration" nhưng code là "Reconnect"

| Concept | Meaning | Quinn Support |
|---------|---------|---------------|
| **Migration** | WiFi → 4G, IP đổi nhưng Connection ID giữ nguyên | ✅ Auto with `disable_active_migration(false)` |
| **Reconnect** | Timeout > threshold, bắt tay lại | ❌ Manual implement needed |

**Revised Approach:**
```rust
fn configure_client() -> ClientConfig {
    let mut transport = TransportConfig::default();

    // Bật QUIC Migration (WiFi ↔ 4G)
    transport.disable_active_migration(false);

    // Timeout 30s cho elevator/tunnel scenarios
    transport.max_idle_timeout(Some(VarInt::from_u32(30_000).into()));

    let mut config = ClientConfig::new(Arc::new(crypto));
    config.transport_config(Arc::new(transport));
    config
}
```

---

### 3. Architecture - Core Library Pattern

**Plan Problem:** Phase 05 code nằm ở đâu?

**Revised Architecture:**
```
crates/core/src/transport/    ← Phase 05 output
├── mod.rs                    → configure_client(), configure_server()
├── stream.rs                 → pump_pty_to_network(), pump_network_to_pty()
└── session.rs                → reconnect logic

crates/mobile_bridge/         ← Consumer của transport
└── src/quic_client.rs        → Import từ core, không tự code

crates/cli_client/            ← Consumer của transport
└── src/main.rs               → Import từ core
```

**Benefits:** Fix bug 1 chỗ → ngon cho cả Mobile + CLI

---

## Revised Phase 05 Plan

### What EXISTS (Don't Reimplement)

| Component | Status | Location |
|-----------|--------|----------|
| MessageCodec | ✅ Done | `crates/core/src/protocol/codec.rs` |
| NetworkMessage | ✅ Done | `crates/core/src/types/message.rs` |
| Quinn handshake | ✅ Done | `quic_client.rs`, `quic_server.rs` |
| TOFU verification | ✅ Done | `TofuVerifier` |

### What TO DO (Revised)

| Step | Old (Plan) | New (Revised) | Effort |
|------|------------|---------------|--------|
| 1 | Transport Abstraction | Config helpers (enable migration, timeout) | 1h |
| 2 | Stream Management | `pump_pty_to_network()`, `pump_network_to_pty()` | 2h |
| 3 | Flow Control | ~~DELETE~~ - Use Quinn's built-in | 0h |
| 4 | Heartbeat | Ping/Pong interval + timeout detect | 1h |
| 5 | Migration/Reconnect | Config migration + reconnect logic | 2h |

**Total:** ~6h (vs 10h originally)

---

## Critical Implementation Details

### 1. Stream Pump (The Real Work)

```rust
// crates/core/src/transport/stream.rs
use quinn::{SendStream, RecvStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub async fn pump_pty_to_quic(
    mut pty: Box<dyn AsyncReadExt + Unpin + Send>,
    mut send: SendStream,
) -> Result<()> {
    let mut buf = vec![0u8; 8192];
    loop {
        let n = pty.read(&mut buf).await?;
        if n == 0 { break; }
        send.write_all(&buf[..n]).await?;  // Quinn handles backpressure
    }
    send.finish().await?;
    Ok(())
}

pub async fn pump_quic_to_pty(
    mut recv: RecvStream,
    mut pty: Box<dyn AsyncWriteExt + Unpin + Send>,
) -> Result<()> {
    let mut buf = vec![0u8; 8192];
    loop {
        let n = recv.read(&mut buf).await?;
        if n == 0 { break; }
        pty.write_all(&buf[..n]).await?;
    }
    Ok(())
}
```

### 2. Heartbeat (Simple)

```rust
// crates/core/src/transport/heartbeat.rs
use tokio::time::{interval, Duration};

pub struct Heartbeat {
    last_activity: Arc<std::sync::atomic::AtomicU64>,
}

impl Heartbeat {
    pub fn spawn(mut tx: SendStream, timeout: Duration) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_secs(5));
            loop {
                ticker.tick().await;
                // Send ping via MessageCodec
                let msg = NetworkMessage::ping();
                let encoded = MessageCodec::encode(&msg)?;
                tx.write_all(&encoded).await?;
            }
        })
    }
}
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `crates/core/src/transport/mod.rs` | Config helpers, re-exports |
| `crates/core/src/transport/stream.rs` | pump_pty_to_quic, pump_quic_to_pty |
| `crates/core/src/transport/heartbeat.rs` | Ping/Pong logic |
| `crates/core/src/transport/reconnect.rs` | Exponential backoff reconnect |

---

## Success Criteria (Revised)

| Criteria | Test Method |
|----------|-------------|
| Commands reach server | Run `ls` in PTY, see output |
| Output streams back | Type in PTY, see on phone |
| Reconnect works | Kill network, restore, verify reconnect |
| Migration works | WiFi → 4G switch (manual test) |
| Latency <100ms | `ping` timestamp diff |

---

## Decision Required

User feedback: Plan cần revise theo 3 điểm trên.

**Next Action:** Tạo plan mới cho Phase 05?

---

## Unresolved Questions

1. **Heartbeat interval:** 5s có quá ngắn không? Battery impact trên mobile?
2. **Reconnect strategy:** Có cần persist session state hay reconnect = clean slate?
3. **Test strategy:** Integration test với real QUIC connection hay mock?

---

---

## Bugs Fixed in Plan (2026-01-07)

### Bug #1: Duplicate Data in `pump_pty_to_quic` (CRITICAL)

**Original code:**
```rust
send.write_all(&buf[..n]).await?;  // ❌ Raw bytes
let encoded = MessageCodec::encode(&msg)?;
send.write_all(&encoded).await?;   // ❌ Encoded message
```

**Problem:** Receiver expects 4 bytes length prefix first. Raw bytes corrupt protocol.

**Fixed:**
```rust
let msg = NetworkMessage::Event(...);
let encoded = MessageCodec::encode(&msg)?;
send.write_all(&encoded).await?;  // ✅ Send ONCE
```

---

### Bug #2: Heartbeat Shared State (Logic)

**Original code:**
```rust
pub fn spawn(...) {
    let last_activity = Arc::new(...);  // ❌ Local variable
    // ...uses last_activity_clone
}
pub fn record_activity(&self) {
    self.last_activity.store(...);  // Updates struct's Arc
}
```

**Problem:** `record_activity()` updates struct's Arc, but `spawn()` uses local Arc → always timeout.

**Fixed:**
```rust
pub fn spawn(
    ...,
    last_activity: Arc<AtomicU64>,  // ✅ Receive shared state
) { ... }

pub fn shared_activity(&self) -> Arc<AtomicU64> {
    self.last_activity.clone()  // ✅ Expose for spawn()
}
```

---

### Bug #3: Heartbeat Timeout Logic (Math)

**Original code:**
```rust
let last_secs = last_activity.load(Ordering::Relaxed);
let last_instant = Instant::now() - Duration::from_secs(last_secs);
let elapsed = Instant::now().duration_since(last_instant);
```

**Problem:** `last_secs` là timestamp (giây kể từ app start), không phải duration. `Instant::now() - Duration` tạo ra Instant sai → tính toán elapsed sai.

**Fixed:**
```rust
// ✅ CORRECT: So sánh timestamp trực tiếp
let current_secs = Instant::now().elapsed().as_secs();  // e.g. 5000
let last_secs = last_activity.load(Ordering::Relaxed);  // e.g. 4950
let idle_secs = current_secs.saturating_sub(last_secs); // 50s

if idle_secs > timeout.as_secs() {
    return Err(CoreError::Timeout);
}
```

---

**Report Status:** All 3 bugs fixed, plan ready for implementation
**Plan Update:** Completed - Phase 05 plan revised with all fixes
**Total Bugs Found & Fixed:** 3 (Duplicate data, Shared state, Timeout logic)
