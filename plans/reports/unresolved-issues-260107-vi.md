# Unresolved Issues - Comacode MVP

**Ngày**: 2026-01-07
**Plan**: 260107-0858-brainstorm-implementation
**Status**: Phase 01-07 completed, remaining issues listed below

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
| 07: Auth Validation + Token Expiry | ✅ Done | Integrated TokenStore validation, 7-day TTL |

---

## Resolved Issues (Phase 07)

~~### 1. Auth Validation Not Integrated~~ ✅ **FIXED**
- TokenStore validation now integrated in quic_server.rs Hello handler
- Rate limiting integrated with auth failures
- See commit `67dad1b`

~~### 2. Token Expiry Missing~~ ✅ **FIXED**
- TokenStore: HashMap<AuthToken, SystemTime> tracks creation time
- 7-day TTL (DEFAULT_TOKEN_TTL)
- Periodic cleanup task (hourly) removes expired tokens
- See commit `67dad1b`

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

| Issue | Severity | Estimate | Priority | Status |
|-------|----------|----------|----------|--------|
| Auth validation not integrated | Medium | 1-2h | **P0** - Security | ✅ Fixed (Phase 07) |
| Token expiry missing | Medium | 2-3h | P1 - Security | ✅ Fixed (Phase 07) |
| IP ban not persistent | Low | 2-3h | P2 - Hardening | Open |
| Flutter bridge not validated | Unknown | 4-6h | P1 - Mobile | Open |
| No integration tests | Low | 3-4h | P2 - QA | Open |

---

## Remaining Work

### Short-term (P1)
1. **Validate Flutter bridge** - Mobile app blocking (separate project)

### Long-term (P2)
2. **Persist IP bans** - Better enforcement (JSON/SQLite)
3. **Add integration tests** - Prevent regressions (QUIC, auth, multi-client)

---

**Last updated**: 2026-01-07

---

## Issue Tracking Update (2026-01-07 14:44)

**Decision**: P1 (Flutter) defer to mobile project, P2 items tracked in technical debt file.

**See**: `plans/260106-2127-comacode-mvp/known-issues-technical-debt.md`
