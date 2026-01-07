# Research Report: QUIC Protocol (quinn) cho Terminal Streaming Latency Thấp

**Ngày nghiên cứu:** 2026-01-06
**Mục tiêu:** Đánh giá QUIC với quinn crate cho streaming terminal latency thấp

---

## Executive Summary

QUIC mang lại lợi thế đáng kể so với TCP cho terminal streaming nhờ 0-RTT handshake, giảm HOL blocking, và connection migration. Quinn crate đã production-ready và ổn định. Đặc biệt phù hợp cho mobile use-case.

**Khuyến nghị:** Sử dụng QUIC/quinn cho terminal streaming khi cần low-latency và network mobility. Cân nhắc TCP cho môi trường mạng cực kỳ ổn định.

---

## Key Findings

### 1. QUIC vs TCP - So sánh Latency

**QUIC advantages:**
- **Connection setup:** 0-1 RTT vs TCP+TLS 2-3 RTT
- **Handshake:** QUIC tích hợp TLS 1.3 → 1 round trip thay vì 2-3 như TCP+TLS
- **HOL blocking:** QUIC multiplexes streams → packet loss ở stream này không block stream khác
- **Packet loss handling:** Tốt hơn trên mạng không ổn định (mobile, wireless)
- **Connection migration:** WiFi ↔ 4G seamless transition

**TCP considerations:**
- Nhanh hơn trên điều kiện mạng lý tưởng (no packet loss, low latency)
- User-space overhead của QUIC có thể impact latency trong điều kiện perfect network

**Kết luận:** QUIC thắng cho real-world terminal streaming, đặc biệt trên mobile.

---

### 2. Quinn Crate Status & Stability

**Trạng thái 2024-2025:**
- ✅ Production-ready, battle-tested
- ✅ Active development, large download count
- ✅ Pure-Rust implementation
- ✅ Tuân thủ IETF QUIC specification

**Độ tin cậy:** Cao. Được sử dụng trong production environment.

---

### 3. 0-RTT Connection Setup

**Cơ chế:**
1. First connection: Server issue session ticket với cryptographic params
2. Client cache session ticket + params (ALPN, address validation tokens)
3. Reconnect: Client gửi `ClientHello` với early data flag + PSK identifier
4. **Application data gửi ngay lập tức** trong first packet (0-RTT)
5. Server decrypt với PSK, process data ngay
6. Full handshake hoàn thành background để establish forward-secret keys

**Yêu cầu:**
- Phải có prior connection để nhận session ticket
- Server phải enable 0-RTT support
- Client phải cache session tickets securely

**Security considerations:**
- ⚠️ **Replay attacks:** 0-RTT data không có forward secrecy → attacker có thể replay
- **Mitigation:** Chỉ dùng 0-RTT cho idempotent operations (GET, read-only)
- Server phải implement replay protection
- Client phải handle reject từ server (re-send data sau 1-RTT)

---

### 4. Connection Migration (WiFi → 4G)

**Cơ chế:**
- QUIC dùng **Connection ID** thay vì IP+port để identify connection
- Khi IP thay đổi (WiFi → 4G), connection ID giữ nguyên → session persists

**Reliability 2024:**
- ✅ Seamless handoffs working well
- ✅ Không bị buffering/drops như TCP (vì TCP reset connection khi IP thay đổi)
- ✅ Enhanced variants (mQUIC) còn tốt hơn
- ✅ HTTP/3 default enabled trên modern OSes

**Edge cases:** Một số trường hợp corner case vẫn đang được research.

---

### 5. Head-of-Line Blocking Elimination

**TCP HOL blocking:**
- 1 lost packet → toàn bộ stream blocked until retransmission
- Window size = packet size × RTT

**QUIC solution:**
- **Stream independence:** Mỗi stream có riêng packet sequencing
- Lost packet ở stream A không ảnh hưởng stream B, C, D...
- **Benefit cho terminal:** Output streams, input streams, metadata streams độc lập → terminal responsive hơn

**Impact:** Significantly improved throughput và perceived responsiveness trên lossy networks.

---

### 6. Message Ordering Guarantees

**Per-stream ordering:**
- Within each stream: **FIFO guaranteed** (TCP-like)
- Across streams: **No ordering guarantee**

**Use case mapping:**
- Terminal output: Dùng 1 stream → preserve order
- Multiple terminal sessions: Mỗi session 1 stream → independent ordering
- File transfers: Dùng dedicated stream per file

---

### 7. Resource Usage on Mobile

**CPU:**
- QUIC user-space implementation → higher CPU overhead than kernel-space TCP
- TLS 1.3 encryption adds overhead
- **Impact:** Moderate impact trên battery life

**Memory:**
- Connection state management heavier than TCP
- Session tickets cache
- **Impact:** Manageable trên modern smartphones

**Network:**
- QUIC headers larger than TCP (~30-40 bytes vs 20 bytes)
- 0-RTT reduces total packets → net bandwidth benefit
- **Impact:** Negligible cho terminal text data

**Battery:**
- User-space crypto + connection tracking → higher drain
- Connection migration → fewer reconnections → saves battery
- **Net impact:** Likely neutral đến slightly positive cho mobile terminal use case

---

## Implementation Recommendations

### Quick Start với Quinn

```rust
// Dependency
// quinn = "0.11"

use quinn::{Endpoint, NewConnection};

// Client
async fn connect_quic() -> Result<()> {
    let mut endpoint = Endpoint::client("[::]:0".parse()?)?;
    endpoint.set_default_client_config(config);

    // 0-RTT nếu có session ticket từ trước
    let connection = endpoint
        .connect(server_addr, "server.example.com")?
        .await?;

    let (mut send, mut recv) = connection
        .open_bi()
        .await?;

    // Send data
    send.write_all(b"terminal command").await?;

    Ok(())
}
```

### Best Practices

1. **0-RTT:** Chỉ dùng cho idempotent operations
2. **Streams:** 1 stream per logical channel (stdin, stdout, stderr)
3. **Connection migration:** Enable cho mobile clients
4. **Session tickets:** Cache persistently để benefit từ 0-RTT
5. **Replay protection:** Server-side mandatory
6. **Fallback:** Implement TCP fallback cho trường hợp QUIC blocked

---

## Comparative Summary

| Factor | QUIC | TCP |
|--------|------|-----|
| Connection Setup | 0-1 RTT | 2-3 RTT |
| HOL Blocking | No (per-stream) | Yes (connection-wide) |
| Connection Migration | Yes (WiFi↔4G) | No (reset on IP change) |
| Security | TLS 1.3 built-in | Separate TLS layer |
| Overhead | Higher (user-space) | Lower (kernel) |
| Mobile Performance | Better | Worse on network change |

---

## Open Questions

1. **Quinn benchmark numbers:** Cần specific latency benchmarks (ms) cho terminal workload
2. **Session ticket rotation:** Best practice cho ticket lifetime trên mobile?
3. **Android/iOS QUIC support:** OS-level integration status?
4. **Battery impact real-world:** Actual measurements trên devices?

---

## Sources

- QUIC vs TCP terminal streaming: gemini research 2024-2025
- Quinn crate stability: gemini research production status
- 0-RTT mechanics: TLS 1.3 specification + QUIC RFC
- Connection migration: Q-MOFI research 2024
- HOL blocking: QUIC RFC 9000

---

**Next Steps:**
1. Prototype terminal over QUIC với quinn
2. Benchmark latency vs TCP trên simulated lossy network
3. Test connection migration trên real devices (WiFi ↔ 4G)
4. Measure battery impact trên Android/iOS
