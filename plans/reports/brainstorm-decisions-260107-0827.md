# Brainstorm Decisions - Comacode MVP

**Ngày**: 2026-01-07
**Scope**: Phase 01-03 Architecture & Implementation Decisions

---

## Phase 1: Build & Deploy

| Topic | Decision | Rationale |
|-------|----------|-----------|
| CI/CD | **Skip** - deploy sau | MVP focus, CI/CD phức tạp với FRB codegen |
| Platform Priority | **macOS First, Windows Ready** | Dev dùng Mac nhiều hơn. Unix-based easier to build. Windows support later. |
| Testing | **Trust Compiler + Manual Dogfooding** | FRB v2 type safety đủ tốt. Integration test tốn effort |
| Code Signing | **Defer** | MVP không cần cert phí $300-400/năm |
| Version Sync | **Shared Constant in Core** | `core/src/lib.rs`: `PROTOCOL_VERSION`, `APP_VERSION_STRING` |

**Implementation**:
```rust
// crates/core/src/lib.rs
pub const PROTOCOL_VERSION: u32 = 1;
pub const APP_VERSION_STRING: &str = "0.1.0-mvp";
```

---

## Phase 2: Protocol & Network

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Protocol Versioning | **Strict Handshake** | Team nhỏ, không support backward compatibility |
| Message Size | **QUIC Streams API** | PTY stream không bao giờ đạt 16MB. File transfer dùng streams |
| Error Recovery | **Stateless Snapshot Resync** | Đơn giản như Option 2, hiệu quả như Option 1 |
| Network Testing | **Local Simulation + Manual** | Toxiproxy tools available nhưng test manual đủ cho MVP |

**Snapshot Resync Logic**:
```
Client (mất kết nối > 5s):
→ Hiện "Reconnecting..."
→ Reconnect thành công → Gửi Packet::RequestSnapshot

Host (nhận RequestSnapshot):
→ Gửi toàn bộ viewport buffer (1000 lines + 24 current)
→ Client resync instantly
```

---

## Phase 3: Output & Security

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Output Streaming | **Channel-based (Actor Model)** | Reader Task → Channel(1024) → Writer Task. Không dùng Arc<Mutex> |
| Certificate Persistence | **Persist + TOFU** | UX tốt, trust on first use với QR fingerprint |
| Session Cleanup | **15min Grace Period** | 30s interval check, 15min timeout cho reconnection |
| Authentication | **Token-based (32-byte)** | Balance UX vs security. Token trong QR code |
| Rate Limiting | **Full (governor crate)** | 5 attempts/min + IP ban. Anti brute-force |

**Channel-based Streaming**:
```rust
// Bounded channel cho natural backpressure
let (tx, rx) = mpsc::channel(1024);

// Reader task: PTY → Channel
// Writer task: Channel → QUIC Stream
// Full = natural backpressure (PTY chặn write)
```

**Token Auth Flow**:
```
1. PC sinh 32-byte Token
2. QR code: IP + Port + Cert Fingerprint + Token
3. Mobile scan QR → save Token
4. Connect: Token trong QUIC header
5. PC verify: match → allow, mismatch → drop
```

---

## Summary Table

| Category | Decision | Priority | Effort |
|----------|----------|----------|--------|
| CI/CD | Skip | P2 | - |
| Platform | Windows only | P0 | Low |
| Testing | Manual dogfooding | P1 | Low |
| Code Signing | Defer | P3 | - |
| Version sync | Core constant | P0 | Low |
| Protocol versioning | Strict | P0 | Low |
| Message size | Streams API | P0 | Medium |
| Error recovery | Snapshot resync | P0 | Medium |
| Network testing | Manual | P2 | Low |
| Output streaming | Channel-based | P0 | High |
| Certificate | Persist + TOFU | P0 | Medium |
| Session cleanup | 15min grace | P1 | Low |
| Authentication | Token-based | P0 | Medium |
| Rate limiting | Full (governor) | P1 | Medium |

---

## Next Steps

1. **Implement Core Constants** - Add `PROTOCOL_VERSION`, `APP_VERSION_STRING` vào `core/src/lib.rs`
2. **Windows Build** - Setup cross-compilation hoặc native build
3. **Channel-based Streaming** - Refactor Phase 03 output forwarding
4. **Certificate Persistence** - Implement `dirs` crate integration
5. **Snapshot Resync** - Add `RequestSnapshot` message type

---

## Unresolved Questions

1. Token distribution: QR code hay manual entry?
2. Governor crate configuration: 5/min có quá strict không?
3. Snapshot buffer size: 1000 lines có đủ không?
4. Windows ConPTY fallback: Có support Windows 7/8 không?
