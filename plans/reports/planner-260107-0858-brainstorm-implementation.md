---
title: "Implementation Plan - Comacode MVP Brainstorm Decisions"
date: 2026-01-07
type: implementation
slug: brainstorm-implementation
status: completed
---

## Implementation Plan Created

**Location**: `plans/260107-0858-brainstorm-implementation/`

**Total Effort**: 28 hours (6 phases)

## Plan Structure

```
plans/260107-0858-brainstorm-implementation/
├── plan.md                           # Overview (<80 lines)
├── phase-01-core-enhancements.md     # Version constants, strict handshake, snapshot resync (3h)
├── phase-02-output-streaming.md      # Channel-based architecture refactor (6h)
├── phase-03-security-hardening.md    # Token auth, rate limiting, IP banning (6h)
├── phase-04-cert-persistence.md      # Cert storage, QR code, TOFU (5h)
├── phase-05-macos-build.md          # macOS build, dogfooding, testing (4h)
└── phase-06-windows-cross.md        # Windows support, ConPTY (4h)
```

## Phase Summary

### Phase 01: Core Enhancements (3h) - P0

**Objectives**:
- Add version constants (`PROTOCOL_VERSION`, `APP_VERSION_STRING`)
- Implement strict handshake protocol (no backward compatibility)
- Add snapshot resync message type

**Key Changes**:
- `crates/core/src/lib.rs`: Version constants
- `crates/core/src/types/message.rs`: Updated `Hello` variant, added `RequestSnapshot`/`Snapshot`
- `crates/core/src/error.rs`: New error variants (`ProtocolVersionMismatch`, `InvalidHandshake`)

**Deliverables**:
- ✅ Version constants accessible from all crates
- ✅ Handshake fails on version mismatch
- ✅ Snapshot message serializable via Postcard

### Phase 02: Output Streaming Refactor (6h) - P0

**Objectives**:
- Replace `Arc<Mutex<Vec<u8>>>` with channel-based architecture
- Implement natural backpressure via bounded channel (1024 capacity)
- Add snapshot buffer integration

**Key Changes**:
- `crates/core/src/streaming.rs`: New `OutputStream` module
- `crates/hostagent/src/session.rs`: Refactor PTY loop
- `crates/hostagent/src/snapshot.rs`: `SnapshotBuffer` (1000 lines)

**Architecture**:
```
PTY Reader Task → mpsc::channel(1024) → Network Writer Task
                      ↓
                 Natural backpressure
```

**Deliverables**:
- ✅ Channel-based streaming replaces shared state
- ✅ Backpressure logs during high output
- ✅ No race conditions
- ✅ Snapshot buffer captures terminal state

### Phase 03: Security Hardening (6h) - P0

**Objectives**:
- Implement 32-byte token authentication
- Add rate limiting (5 attempts/min) với governor crate
- Implement IP banning logic

**Key Changes**:
- `crates/core/src/auth.rs`: `AuthToken` type (256-bit)
- `crates/hostagent/src/auth.rs`: `TokenStore`
- `crates/hostagent/src/ratelimit.rs`: `RateLimiterStore` với governor
- `crates/core/src/types/message.rs`: Add `auth_token` to `Hello`

**Dependencies Added**:
```toml
governor = "0.6"  # Rate limiting
rand = "0.8"      # Token generation
```

**Deliverables**:
- ✅ Token generation deterministic from hex
- ✅ Invalid tokens rejected
- ✅ Rate limiter blocks after 5 attempts/min
- ✅ Banned IPs cannot connect

### Phase 04: Certificate Persistence + TOFU (5h) - P0

**Objectives**:
- Persist certificate/key pairs to disk
- Generate QR code (IP + Port + Fingerprint + Token)
- Implement TOFU (Trust On First Use) verification

**Key Changes**:
- `crates/hostagent/src/cert.rs`: `CertStore` (load/save cert pairs)
- `crates/core/src/types/qr.rs`: `QrPayload` (QR data structure)
- `crates/mobile_bridge/src/tofu.rs`: `TofuStore` (known hosts tracking)

**Dependencies Added**:
```toml
dirs = "5.0"   # Cross-platform paths
qrcode = "0.14" # QR generation
```

**UX Flow**:
```
1. Hostagent starts → loads/generates cert + token
2. Displays QR code
3. Mobile scans QR → extracts data
4. Connect → TOFU accepts (first time) or verifies (subsequent)
```

**Deliverables**:
- ✅ Cert persists across restarts
- ✅ QR code contains all required fields
- ✅ TOFU accepts new hosts automatically
- ✅ TOFU rejects changed fingerprints

### Phase 05: macOS Build + Testing (4h) - P1

**Objectives**:
- Build universal macOS binary (M1 + Intel)
- Document manual dogfooding process
- Verify features via local network testing

**Key Changes**:
- `scripts/build-macos.sh`: Universal binary build script
- `docs/dogfooding-guide.md`: Test scenarios + benchmarks
- `.cargo/config.toml`: macOS target configuration

**Test Scenarios**:
1. Basic terminal control
2. Rapid input (backpressure test)
3. Network interruption (snapshot resync)
4. Security features (auth + rate limiting)
5. TOFU verification

**Performance Targets**:
- Binary size: <10MB
- Cold start: <500ms
- Latency: <50ms (local WiFi)
- Throughput: >2MB/s
- Memory: <50MB idle

**Deliverables**:
- ✅ Universal macOS binary
- ✅ Dogfooding guide
- ✅ All test scenarios pass
- ✅ Performance benchmarks met

### Phase 06: Windows Cross-Platform (4h) - P2

**Objectives**:
- Enable Windows build (native or cross-compile)
- Configure ConPTY (Windows pseudo-console)
- Ensure feature parity with macOS

**Key Changes**:
- `scripts/build-windows.sh`: Windows build script
- `crates/hostagent/src/pty/windows.rs`: `WindowsPty` (ConPTY wrapper)
- `docs/platform-support.md`: Compatibility matrix

**Windows-Specific Handling**:
- Force enable ConPTY (Windows 10+ only)
- Line ending normalization (CRLF → LF)
- Path handling (backslash vs forward slash)

**Platform Support**:
| Platform | Status | Notes |
|----------|--------|-------|
| macOS 11+ (M1/Intel) | ✅ Supported | Tested |
| Windows 10+ | ✅ Supported | ConPTY only |
| Windows 8/7 | ❌ Not Supported | ConPTY unavailable |
| Linux | ⚠️ Best Effort | Not tested |

**Deliverables**:
- ✅ Windows binary builds
- ✅ ConPTY session creates
- ✅ All Phase 01-04 features work

## Dependencies

```
Phase 01 → Phase 02 → Phase 03 → Phase 04 → Phase 05 → Phase 06
  (P0)       (P0)       (P0)       (P0)       (P1)       (P2)
```

**Critical Path**: Phases 01-04 must complete before macOS testing (Phase 05).

**Parallel Opportunities**:
- Phase 03 can start after Phase 01 (no dependency on Phase 02)
- Phase 06 can start in parallel with Phase 05 (different platforms)

## Acceptance Criteria

MVP complete khi:
1. ✅ Version constants sync across core/mobile/host
2. ✅ Channel-based streaming hoạt động với backpressure
3. ✅ Token auth + rate limiting enabled
4. ✅ Cert persist + TOFU flow functional
5. ✅ macOS binary runs stable qua dogfooding
6. ✅ Windows build successful (tested if available)

## Key Decisions Applied

**Architecture**:
- ✅ Channel-based streaming (mpsc::channel) thay vì Arc<Mutex>
- ✅ Strict handshake (no backward compatibility)
- ✅ Snapshot resync cho error recovery
- ✅ TOFU verification với QR code

**Security**:
- ✅ 32-byte token authentication
- ✅ Rate limiting với governor crate (5 attempts/min)
- ✅ IP banning logic

**Platform**:
- ✅ macOS first, Windows ready
- ✅ Manual dogfooding (no automated tests)
- ✅ Code signing deferred

## Unresolved Questions

From brainstorm decisions, still unresolved:

1. **QR Code Format** (Phase 04):
   - JSON raw hay base64 encoding?
   - **Decision**: JSON (readable, easier debugging)

2. **Rate Limit Config** (Phase 03):
   - 5 attempts/min có quá strict không?
   - **Decision**: Start with 5, tune based on dogfooding feedback

3. **Snapshot Buffer Size** (Phase 02):
   - 1000 lines có đủ không?
   - **Decision**: Start with 1000, monitor in Phase 05

4. **Windows 7/8 Support** (Phase 06):
   - ConPTY fallback có cần không?
   - **Decision**: No, ConPTY only (Windows 10+)

5. **PowerShell Default** (Phase 06):
   - Default shell: PowerShell hay cmd?
   - **Decision**: cmd for MVP (simpler)

## Next Steps

1. **Start Phase 01**: Add version constants to `crates/core/src/lib.rs`
2. **Setup Workspace**: Create branch `feature/phase-01-core-enhancements`
3. **Track Progress**: Update phase files as tasks complete
4. **Document Issues**: Record blockers/questions in phase files

## File Locations

**Plan Root**: `/Users/khoa2807/development/2026/Comacode/plans/260107-0858-brainstorm-implementation/`

**Main Plan**: `plan.md`

**Phase Files**:
- `phase-01-core-enhancements.md`
- `phase-02-output-streaming.md`
- `phase-03-security-hardening.md`
- `phase-04-cert-persistence.md`
- `phase-05-macos-build.md`
- `phase-06-windows-cross.md`

## Notes

- **Token Efficiency**: Plan files concise (~300 lines each vs typical 500+)
- **Implementation Ready**: Each phase has concrete code examples
- **Test Coverage**: Manual testing strategy per phase
- **Risk Mitigation**: Dependencies and blockers clearly marked

---

**Status**: ✅ Plan complete, ready for implementation
**Session Updated**: Active plan set to `plans/260107-0858-brainstorm-implementation`
