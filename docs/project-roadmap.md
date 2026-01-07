# Project Roadmap

**Project**: Comacode
**Last Updated**: 2026-01-07
**Current Phase**: 04.1 (Post-MVP Bugfix)

---

## Overview

Comacode enables remote terminal access via QR code pairing using QUIC protocol.

**Goal**: Simple, secure way to access remote terminal from mobile device.

---

## Phase Status

| Phase | Name | Status | Completion |
|-------|------|--------|------------|
| 01 | PTY Integration | ✅ Done | 100% |
| 02 | Auth + Rate Limiting | ✅ Done | 100% |
| 03 | QUIC Server | ✅ Done | 100% |
| 04 | QUIC Client (Mobile) | ✅ Done | 100% |
| 04.1 | Critical Bugfixes | ✅ Done | 100% |
| 05 | Network Protocol | ⏳ TODO | 0% |
| 06 | Flutter UI | ⏳ TODO | 0% |
| 07 | Production Hardening | ⏳ TODO | 0% |

---

## Completed Phases

### Phase 01: PTY Integration
- [x] PTY spawn with `ptybo`
- [x] I/O stream handling
- [x] Window size change support

**Deliverable**: `crates/hostagent/src/pty.rs`

---

### Phase 02: Auth + Rate Limiting
- [x] JWT-like token generation (HMAC-SHA256)
- [x] Token validation middleware
- [x] IP-based rate limiting (in-memory)
- [x] Auto-ban on threshold exceeded

**Deliverable**: `crates/hostagent/src/auth.rs`, `crates/hostagent/src/ratelimit.rs`

---

### Phase 03: QUIC Server
- [x] Quinn 0.11 server setup
- [x] Rustls 0.23 with self-signed certs
- [x] Connection management
- [x] Session isolation

**Deliverable**: `crates/hostagent/src/quic_server.rs`

---

### Phase 04: QUIC Client (Mobile)
- [x] Quinn 0.11 client in Rust
- [x] TOFU verification (fingerprint normalization)
- [x] FFI bridge for Flutter
- [x] QR payload parsing

**Deliverable**: `crates/mobile_bridge/src/quic_client.rs`, `crates/mobile_bridge/src/api.rs`

---

### Phase 04.1: Critical Bugfixes
- [x] Fix UB in `api.rs` (replace `static mut` with `once_cell::sync::OnceCell`)
- [x] Fix fingerprint leakage in logs
- [x] Zero unsafe blocks (was 6, now 0)

**Deliverable**: Commit `00b6288`

---

## Upcoming Phases

### Phase 05: Network Protocol (PRIORITY)

**Goal**: Implement actual QUIC stream I/O for terminal communication

**Tasks**:
- [ ] Design wire protocol (message framing, chunking)
- [ ] Implement `receive_event()` with actual QUIC stream reading
- [ ] Implement `send_command()` with actual QUIC stream writing
- [ ] Add reconnection logic
- [ ] Handle stream errors gracefully

**Estimate**: 8-12h

**Dependencies**: None (can start immediately)

---

### Phase 06: Flutter UI

**Goal**: Build mobile app UI

**Tasks**:
- [ ] QR scanner screen
- [ ] Terminal display (xterm.js flutter fork)
- [ ] Connection status indicator
- [ ] Settings (fingerprint management)
- [ ] Test FFI boundary

**Estimate**: 16-24h

**Dependencies**: Phase 05 (Network Protocol)

---

### Phase 07: Production Hardening

**Goal**: Prepare for public release

**Tasks**:
- [ ] IP ban persistence (JSON file)
- [ ] Integration tests
- [ ] Constant-time fingerprint comparison
- [ ] Error message improvements
- [ ] Configurable timeout values
- [ ] Security audit

**Estimate**: 6-8h

**Dependencies**: Phase 06

---

## Technical Debt Tracker

See `plans/260106-2127-comacode-mvp/known-issues-technical-debt.md`

| Issue | Priority | Phase |
|-------|----------|-------|
| Stream I/O stubs | P1 | Phase 05 |
| IP ban persistence | P2 | Phase 07 |
| Integration tests | P2 | Phase 07 |
| Constant-time comparison | P3 | Phase 07 |
| Hardcoded timeout | P2 | Phase 07 |
| Generic error messages | P2 | Phase 07 |

---

## Timeline

```
2026-01-06  │ Phase 01-03: MVP Complete
2026-01-07  │ Phase 04: QUIC Client Complete
2026-01-07  │ Phase 04.1: Bugfixes Complete
────────────┼────────────────────────────
TBD         │ Phase 05: Network Protocol
TBD         │ Phase 06: Flutter UI
TBD         │ Phase 07: Production Hardening
```

---

## Success Criteria

- [ ] Mobile app can connect to hostagent via QR scan
- [ ] Terminal I/O works bidirectionally
- [ ] TOFU verification prevents MitM
- [ ] Rate limiting protects against abuse
- [ ] Production-ready (hardened, tested)
