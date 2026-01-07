# Known Issues & Technical Debt

**Status**: MVP Complete, tracking post-MVP improvements
**Updated**: 2026-01-07
**Parent Plan**: 260106-2127-comacode-mvp

---

## Overview

MVP (Phase 01-07) hoàn thành. File này track các issues P2 (hardening) và P1 (separate projects) chưa được implement.

**Định nghĩa Priority:**
- **P1**: Important but không block MVP hiện tại
- **P2**: Nice-to-have, hardening/optimization

---

## P2: Post-MVP Hardening

### 1. IP Ban Not Persistent

**Severity**: Low
**Location**: `crates/hostagent/src/ratelimit.rs`

**Problem**:
```rust
// Current: In-memory only, lost on restart
pub struct RateLimiterStore {
    banned_ips: Arc<Mutex<HashMap<IpAddr, BanReason>>>
}
```

**Impact**:
- Attacker chỉ cần restart hostagent để bypass ban
- Không có enforcement lâu dài

**Fix Required**:
- Persist bans to file (JSON đủ, SQLite overkill)
- Load bans on startup
- Ban expiry time (configurable, default 1h)

**Files to Modify**:
```
crates/hostagent/src/
├── ratelimit.rs    # Add load/save methods
└── main.rs         # Load bans on startup
```

**Estimate**: 2-3h

**Questions**:
- Ban duration: temporary (1h) hay permanent?
- Format: JSON hay SQLite?

---

### 2. No Integration Tests

**Severity**: Low
**Location**: `tests/` (không tồn tại)

**Problem**:
- Chỉ có unit tests
- Không có end-to-end tests cho:
  - QUIC connection flow
  - Auth + rate limiting interaction
  - Multi-client scenarios

**Impact**:
- Regressions có thể sneaking in
- Manual testing required cho every change

**Fix Required**:
```rust
tests/
├── integration/
│   ├── quic_connection_test.rs     # Full QUIC handshake
│   ├── auth_flow_test.rs            # Token validation + rate limit
│   └── multi_client_test.rs         # Concurrent connections
```

**Estimate**: 3-4h

**Dependencies**:
- Need test helper utilities (mock QUIC client)
- May need `tokio::test` with additional setup

---

## P1: Separate Projects

### 3. QUIC Client Missing from Mobile Bridge

**Severity**: High (Blocker cho mobile)
**Location**: `crates/mobile_bridge/src/`

**Problem**:
- Flutter expects `connectToHost(host, port, token, fingerprint)`
- Rust bridge chỉ có encode/decode functions
- QUIC client chưa implement

**Impact**:
- Mobile app **KHÔNG THỂ** kết nối đến host
- Blocker cho Phase 04 (Mobile App)

**Fix Required**:
- Implement `QuicClient` struct với quinn
- Add `connectToHost()` FFI function
- Handle TOFU verification (auto-trust flow)

**See**: `plans/reports/brainstorming-260107-1450-phase04-mobile-revised.md`

**Estimate**: 8-12h

---

### 4. Flutter Bridge Not Validated

**Severity**: Unknown (blocking cho mobile)
**Location**: `crates/mobile_bridge/`

**Problem**:
- `mobile_bridge` crate đã generate với flutter_rust_bridge
- Chưa test FFI boundary với Flutter app thật
- Chưa verify data serialization across FFI

**Impact**:
- Có thể có bug khi Flutter app call Rust functions
- Type mismatch, null pointer, encoding issues

**Fix Required**:
- Build Flutter app (separate project)
- Test từng FFI function
- Integration tests với real device/simulator

**Note**: Đây là **separate project** - không phải part của hostagent binary.

**Estimate**: 4-6h (part of mobile project development)

---

## Summary Table

| Issue | Priority | Estimate | Blocker? | Action |
|-------|----------|----------|----------|--------|
| IP ban not persistent | P2 | 2-3h | No | JSON persistence |
| No integration tests | P2 | 3-4h | No | Add test suite |
| QUIC client missing | **P0** | 8-12h | **Yes (mobile)** | Implement in Rust |
| Flutter bridge not validated | P1 | 4-6h | Yes (mobile) | Defer to Flutter project |

---

## When to Implement

### Before Public Release
- **IP Ban Persistence**: Recommended nếu deploy cho public users
- **Integration Tests**: Recommended nếu có multiple contributors

### During Flutter Development
- **Flutter Bridge Validation**: Part of mobile project setup

### Can Defer Indefinitely
- All items are optional for personal/single-user MVP

---

## Unresolved Questions

1. **IP Ban Format**: JSON đủ hay cần SQLite?
2. **Ban Duration**: 1h default, hay configurable via flag?
3. **Integration Test Priority**: Manual testing đủ tốt cho MVP?

---

**Last updated**: 2026-01-07
**Next review**: Trước khi implement bất kỳ item nào
