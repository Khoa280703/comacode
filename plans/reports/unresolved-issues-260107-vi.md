# Unresolved Issues - Comacode MVP

**Ngày**: 2026-01-07
**Plan**: 260107-0858-brainstorm-implementation
**Status**: Phase 01-06 completed, issues listed below

---

## Phase Completion Status

| Phase | Status | Notes |
|-------|--------|-------|
| 01: Core Enhancements | ✅ Done | TerminalConfig, shell detection, error types |
| 02: Output Streaming | ✅ Done | Channel-based, bytes::Bytes, spawn_blocking |
| 03: Security Hardening | ✅ Done | AuthToken, TokenStore, RateLimiterStore |
| 04: Certificate + TOFU | ✅ Done | Cert persistence, QR code, TofuStore |
| 05: macOS Build + Testing | ✅ Done | Build script, CLI client, dogfooding guide, network test |
| 06: Windows Cross-Platform | ✅ Done | GitHub Actions CI (Windows build) |

---

## Issues Not Covered in Phase 4-6

### 1. Auth Validation Not Integrated

**Severity**: Medium
**Location**: `crates/hostagent/src/quic_server.rs`

**Problem**:
- `TokenStore` và `RateLimiterStore` đã implement nhưng **KHÔNG được sử dụng** trong QUIC server
- Client có thể kết nối mà không cần validate token thực sự

**Current Code**:
```rust
// crates/hostagent/src/quic_server.rs
// Token được nhận từ Hello message nhưng KHÔNG validate
let token = hello.token;  // Just extracted, not validated
// TODO: Integrate TokenStore::validate()
```

**Impact**:
- Auth không hoạt động như thiết kế
- Bypass token có thể kết nối

**Fix Required**:
```rust
// Trong quic_server.rs connection handler
if let Some(token) = hello.token {
    if !self.token_store.validate(token).await {
        return Err(CoreError::InvalidToken);
    }
}
```

**Estimate**: 1-2h

---

### 2. Token Expiry Missing

**Severity**: Medium
**Location**: `crates/core/src/auth.rs`

**Problem**:
- `AuthToken` không có TTL (time-to-live)
- Token hợp mãi mã, không có cơ chế refresh/revoke

**Current Code**:
```rust
// crates/core/src/auth.rs
pub struct AuthToken([u8; 32]);
// NO expiry timestamp!
```

**Impact**:
- Security risk: token bị leak → lifetime mãi mã
- Không thể revoke token khi cần

**Fix Required**:
```rust
pub struct AuthToken {
    bytes: [u8; 32],
    expires_at: SystemTime,  // Add TTL
}

impl AuthToken {
    pub fn is_expired(&self) -> bool {
        SystemTime::now() > self.expires_at
    }
}
```

**Questions**:
- TTL là bao nhiêu? (24h, 7d, 30d)
- Refresh token mechanism?

**Estimate**: 2-3h

---

### 3. IP Ban Not Persistent

**Severity**: Low
**Location**: `crates/hostagent/src/ratelimit.rs`

**Problem**:
- `RateLimiterStore` lưu IP bans trong **memory only**
- Restart hostagent → mất tất cả bans

**Current Code**:
```rust
// crates/hostagent/src/ratelimit.rs
use std::collections::HashMap;  // In-memory only!
pub struct RateLimiterStore {
    banned_ips: Arc<Mutex<HashMap<IpAddr, BanReason>>>  // Lost on restart
}
```

**Impact**:
- Attacker chỉ cần restart hostagent để bypass ban
- Không có enforcement lâu dài

**Fix Required**:
- Persist bans to file (JSON/SQLite)
- Load bans on startup

**Questions**:
- SQLite hay JSON đủ?
- Temporary (1h) hay permanent bans?

**Estimate**: 2-3h

---

### 4. Flutter Bridge Not Validated

**Severity**: Unknown
**Location**: `crates/mobile_bridge/`

**Problem**:
- `mobile_bridge` crate đã generate với flutter_rust_bridge
- Chưa test FFI boundary với Flutter app thật
- Chưa verify data serialization across FFI

**Impact**:
- Có thể có bug khi Flutter app call Rust functions
- Type mismatch, null pointer, etc.

**Fix Required**:
- Build Flutter app
- Test từng FFI function
- Integration tests

**Note**: Đây là **separate project** (mobile app), không phải part của hostagent binary.

**Estimate**: 4-6h (Flutter app setup + testing)

---

### 5. No Integration Tests

**Severity**: Low
**Location**: `tests/` (không tồn tại)

**Problem**:
- Chỉ có unit tests
- Không có integration tests cho:
  - QUIC connection flow
  - Auth + rate limiting interaction
  - Multi-client scenarios

**Impact**:
- Regressions có thể sneaking in
- Manual testing required cho every change

**Fix Required**:
```
tests/
├── integration/
│   ├── quic_connection_test.rs
│   ├── auth_flow_test.rs
│   └── multi_client_test.rs
```

**Estimate**: 3-4h

---

## Summary

| Issue | Severity | Estimate | Priority |
|-------|----------|----------|----------|
| Auth validation not integrated | Medium | 1-2h | **P0** - Security |
| Token expiry missing | Medium | 2-3h | P1 - Security |
| IP ban not persistent | Low | 2-3h | P2 - Hardening |
| Flutter bridge not validated | Unknown | 4-6h | P1 - Mobile |
| No integration tests | Low | 3-4h | P2 - QA |

---

## Recommendations

### Immediate (P0)
1. **Integrate auth validation** in QUIC server - Critical security issue

### Short-term (P1)
2. **Add token expiry** - Security best practice
3. **Validate Flutter bridge** - Mobile app blocking

### Long-term (P2)
4. **Persist IP bans** - Better enforcement
5. **Add integration tests** - Prevent regressions

---

**Last updated**: 2026-01-07
