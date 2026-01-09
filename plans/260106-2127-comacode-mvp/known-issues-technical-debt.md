# Known Issues & Technical Debt

**Status**: MVP Complete, tracking post-MVP improvements
**Updated**: 2026-01-08 (Post-Phase 05.1 - Terminal Streaming Integration)
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

**Status**: ✅ **COMPLETED** (2026-01-07)

**Problem**:
- Flutter expects `connectToHost(host, port, token, fingerprint)`
- Rust bridge chỉ có encode/decode functions
- ~~QUIC client chưa implement~~

**Impact**:
- ~~Mobile app **KHÔNG THỂ** kết nối đến host~~
- ~~Blocker cho Phase 04 (Mobile App)~~

**Fix Applied**:
- ✅ Implemented `QuicClient` struct với Quinn 0.11 + Rustls 0.23
- ✅ Added `connectToHost()` FFI function
- ✅ TOFU verification (Trust On First Use)
- ✅ Fingerprint normalization (case-insensitive, separator-agnostic)

**See**: `plans/260107-1553-solve-quinn-quic-client/plan.md`

**Completed by**: Commit `352645a`

---

### 4. Flutter Bridge Not Validated

**Severity**: Unknown (blocking cho mobile)
**Location**: `crates/mobile_bridge/`
**Status**: ✅ **COMPLETED** (2026-01-07)

**Problem**:
- ~~`mobile_bridge` crate đã generate với flutter_rust_bridge~~
- ~~Chưa test FFI boundary với Flutter app thật~~
- ~~Chưa verify data serialization across FFI~~

**Fix Applied**:
- ✅ Generated FRB bindings với `flutter_rust_bridge_codegen`
- ✅ Created `BridgeWrapper` với error handling
- ✅ QR scanner validates QR payload
- ✅ Terminal UI receives events via FRB

**See**: Phase 06 Flutter UI

**Completed by**: Phase 06

---

## P1: Phase 04 Post-Implementation Issues

### 5. Undefined Behavior in FFI Bridge (CRITICAL)

**Severity**: High (UB risk - data races, segfaults)
**Location**: `crates/mobile_bridge/src/api.rs:15-114`
**Status**: ✅ **COMPLETED** (2026-01-07)

**Problem**:
```rust
// BEFORE: static mut with UB
static mut QUIC_CLIENT: Option<Arc<Mutex<QuicClient>>> = None;
let client_arc = unsafe { QUIC_CLIENT.as_ref().unwrap().clone() };
```

**Impact**:
- ~~Data races if static is mutated while shared reference exists~~
- ~~Potential segfaults in production~~
- ~~Compiler warnings indicate UB risk~~

**Fix Applied**:
```rust
// AFTER: Thread-safe with OnceCell
use once_cell::sync::OnceCell;
static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();

// Zero unsafe blocks needed
let client_arc = QUIC_CLIENT.get()
    .ok_or_else(|| "Not connected".to_string())?;
```

**Result**:
- ✅ Zero unsafe blocks (was 6, now 0)
- ✅ Zero UB warnings
- ✅ Thread-safe via atomic operations
- ✅ One-time initialization guarantee

**Estimate**: 1h (Actual: ~45 min)

**See**: `plans/260107-1648-fix-critical-ub-fingerprint-leak/plan.md`

**Completed by**: Phase 04.1 Bugfix

---

### 6. Stream I/O Stub Implementation (HIGH)

**Severity**: High (blocks Flutter integration)
**Location**: `crates/mobile_bridge/src/quic_client.rs:229-253`
**Status**: ✅ **COMPLETED** (2026-01-08)

**Problem**:
```rust
// BEFORE: Stub implementation
pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
    // TODO: Actually receive from QUIC stream
    Ok(TerminalEvent::output_str(""))  // STUB!
}

pub async fn send_command(&self, command: String) -> Result<(), String> {
    // TODO: Actually send via QUIC stream
    info!("QUIC client: would send command: {}", command);
    Ok(())
}
```

**Fix Applied**:
- ✅ Implemented actual QUIC stream reading in `receive_event()`
- ✅ Implemented actual QUIC stream writing in `send_command()`
- ✅ Server side: `pump_pty_to_quic()` with tokio utilities
- ✅ Bidirectional PTY ↔ QUIC communication working

**See**: Phase 05.1 Terminal Streaming Integration

**Completed by**: Phase 05.1

---

## P2: Post-Phase 04 Hardening

### 7. Fingerprint Leakage in Logs (MEDIUM)

**Severity**: Medium (security/privacy concern)
**Location**: `crates/mobile_bridge/src/quic_client.rs:88`
**Status**: ✅ **COMPLETED** (2026-01-07)

**Problem**:
```rust
// BEFORE: Full fingerprint logged
debug!("Verifying cert - Expected: {}, Actual: {}", self.expected_fingerprint, actual_clean);
error!("Fingerprint mismatch! Expected: {}, Got: {}", self.expected_fingerprint, actual_clean);
```

**Issue**: ~~Actual fingerprint value logged, extractable from crash reports/debug logs~~

**Fix Applied**:
```rust
// AFTER: Only match result logged (debug)
debug!("Verifying cert - Match: {}", actual_clean == expected_clean);

// Error logs show partial (first 4 + last 4 chars only)
error!("Fingerprint mismatch! Expected: {}...{}, Got: {}...{}",
    expected_prefix, expected_suffix, actual_prefix, actual_suffix);
```

**Result**:
- ✅ Full fingerprint no longer logged
- ✅ Debug shows only boolean match result
- ✅ Error shows only 8 hex chars (first 4 + last 4) instead of 64

**Estimate**: 15 min (Actual: ~10 min)

**See**: `plans/260107-1648-fix-critical-ub-fingerprint-leak/plan.md`

**Completed by**: Phase 04.1 Bugfix

---

### 8. Hardcoded Timeout Value (LOW)

**Severity**: Low (configurability concern)
**Location**: `crates/mobile_bridge/src/quic_client.rs:206`
**Status**: ⚠️ **OPEN**

**Problem**:
```rust
transport_config.max_idle_timeout(Some(Duration::from_secs(10).try_into().unwrap()));
```

**Issue**: 10s timeout hardcoded, not tunable for different network conditions.

**Fix Required**:
```rust
const DEFAULT_IDLE_TIMEOUT_SECS: u64 = 10;
```

**Estimate**: 10 min

---

### 9. Generic Error Messages (LOW)

**Severity**: Low (UX concern)
**Location**: Multiple locations in `quic_client.rs`
**Status**: ⚠️ **OPEN**

**Problem**:
```rust
let connection = connecting.await.map_err(|e| format!("Connection failed: {}", e))?;
```

**Issue**: Missing host:port context in error messages.

**Fix Required**:
```rust
let connection = connecting.await.map_err(|e| {
    format!("Connection failed to {}:{}: {}", host, port, e)
})?;
```

**Estimate**: 15 min

---

### 10. Missing Constant-Time Comparison (NICE-TO-HAVE)

**Severity**: Low (timing attack prevention)
**Location**: `crates/mobile_bridge/src/quic_client.rs:90`
**Status**: ⚠️ **OPEN**

**Problem**:
```rust
if actual_clean == expected_clean { ... }
```

**Issue**: String comparison may leak timing information.

**Fix Required**:
```rust
use subtle::ConstantTimeEq;
if actual_clean.as_bytes().ct_eq(expected_clean.as_bytes()).into() { ... }
```

**Estimate**: 30 min

---

## P1: Phase 06 Post-Implementation Issues

### 11. Token Expiry Not Implemented (HIGH)

**Severity**: High (security concern)
**Location**: `mobile/lib/core/storage.dart:66-74`

**Problem**:
```dart
static Future<void> saveHost(QrPayload payload) async {
    await _storage.write(key: payload.storageKey, value: payload.toJson());
    await _storage.write(key: 'last_host', value: payload.fingerprint);
    // ❌ Không store timestamp
    // ❌ Không store token expiry
}
```

**Impact**:
- TOFU = trust forever, không có revoke mechanism
- Stolen tokens = permanent access
- Violates security best practices

**Fix Required**:
```dart
class QrPayload {
    final DateTime createdAt;      // ✅ Thêm timestamp
    final DateTime? expiresAt;     // ✅ Thêm expiry
}

// Check expiry khi load
if (payload.expiresAt != null && DateTime.now().isAfter(payload.expiresAt!)) {
    await deleteHost(fp); // Auto-revoke expired
    return null;
}
```

**Estimate**: 2-3h

**See**: Phase 07 (Discovery & Auth)

---

### 12. PTY Resize Not Hooked to Screen Rotation (MEDIUM)

**Severity**: Medium (UX issue)
**Location**: `mobile/lib/features/terminal/terminal_page.dart:210-211`

**Problem**:
```dart
int _terminalRows = 24;  // ❌ unused
int _terminalCols = 80;  // ❌ unused
```

- Fields declared but never updated
- Missing screen rotation detection
- Missing `resizePty()` call when orientation changes

**Impact**:
- Terminal output misaligned when screen rotates
- Text wrapping broken
- Poor UX

**Fix Required**:
```dart
void didChangeMetrics() {
    super.didChangeMetrics();
    _updateTerminalSize();
}

void _updateTerminalSize() {
    final screenSize = MediaQuery.of(context).size;
    final newCols = (screenSize.width / 7.5).floor();  // char width
    final newRows = (screenSize.height / 16.0).floor(); // char height

    if (newCols != _terminalCols || newRows != _terminalRows) {
        _terminalCols = newCols;
        _terminalRows = newRows;
        bridge.resizePty(rows: _terminalRows, cols: _terminalCols);
    }
}
```

**Estimate**: 1-2h

---

### 13. Double Parsing QR Redundancy (LOW)

**Severity**: Low (performance concern)
**Location**: `mobile/lib/features/connection/connection_providers.dart:96-126`

**Problem**:
```dart
// Parse to Dart model first (for storage and UI)
final dartPayload = QrPayload.fromJson(qrJson);  // ❌ PARSE 1

// Parse to FRB opaque type
final frbPayload = await bridge.parseQrPayload(qrJson);  // ❌ PARSE 2
```

**Impact**:
- Performance overhead (~2x parsing time)
- Wasted FFI calls (4 getter functions)
- Potential inconsistencies between Dart vs Rust parsing

**Fix Required**:
- Use ONLY Dart model, extract fields directly
- Remove FRB `parseQrPayload()` call
- Pass primitive types to `bridge.connect()`

**Estimate**: 30 min

---

### 14. Silent Error Handling in Event Loop (MEDIUM)

**Severity**: Medium (debugging difficulty)
**Location**: `mobile/lib/features/terminal/terminal_page.dart:245-247`

**Problem**:
```dart
} catch (e) {
    // Ignore errors, continue polling  ❌ Silent!
}
```

**Impact**:
- No visibility into connection failures
- Difficult to debug production issues
- Wasted battery/CPU polling dead connections

**Fix Required**:
```dart
} catch (e) {
    debugPrint('Event loop error: $e');

    // Check if connection lost
    if (e.toString().contains('Not connected') ||
        e.toString().contains('Connection closed')) {
        _isConnected = false;
        // Show user notification
        // Stop polling
        _eventLoopTimer?.cancel();
    }
}
```

**Estimate**: 30 min

---

### 15. Basic QR Validation Only (LOW)

**Severity**: Low (validation concern)
**Location**: `mobile/lib/features/qr_scanner/qr_scanner_page.dart:56-67`

**Problem**:
```dart
bool _isValidQrPayload(String json) {
    // ❌ Không validate IP format
    // ❌ Không validate port range
    // ❌ Không validate fingerprint length
    return decoded['ip'] is String &&
        (decoded['port'] is int) &&
        decoded['token'] is String &&
        decoded['fingerprint'] is String;
}
```

**Impact**:
- Invalid data có thể pass validation
- Runtime errors khi connect với malformed data

**Fix Required**:
- Validate IPv4/IPv6 format
- Validate port range (1-65535)
- Validate fingerprint length (64 hex chars for SHA-256)

**Estimate**: 30 min

---

## Summary Table

| Issue | Priority | Estimate | Blocker? | Action |
|-------|----------|----------|----------|--------|
| IP ban not persistent | P2 | 2-3h | No | JSON persistence |
| No integration tests | P2 | 3-4h | No | Add test suite |
| QUIC client missing | ~~**P0**~~ | ~~8-12h~~ | ~~**Yes**~~ | ✅ **COMPLETED** |
| Flutter bridge not validated | ~~**P1**~~ | ~~**4-6h**~~ | ~~**Yes (mobile)**~~ | ✅ **COMPLETED** |
| **UB in FFI bridge (api.rs)** | ~~**P1**~~ | ~~**1h**~~ | ~~**Yes**~~ | ✅ **COMPLETED** |
| **Stream I/O stubs** | ~~**P1**~~ | ~~**3-4h**~~ | ~~**Yes (Flutter)**~~ | ✅ **COMPLETED** |
| Fingerprint leakage in logs | ~~**P2**~~ | ~~**15 min**~~ | ~~**No**~~ | ✅ **COMPLETED** |
| **Token expiry not implemented** | **P1** | **2-3h** | **No** | **Phase 07** |
| **PTY resize not hooked** | **P2** | **1-2h** | **No** | **Phase 07** |
| **Double parsing QR** | P3 | 30 min | No | Remove FRB parse |
| **Silent error handling** | P2 | 30 min | No | Add logging |
| **Basic QR validation** | P3 | 30 min | No | Add format checks |
| Hardcoded timeout | P2 | 10 min | No | Add const |
| Generic error messages | P2 | 15 min | No | Add host:port context |
| Constant-time comparison | P3 | 30 min | No | Use `subtle` crate |

### Completed (2026-01-08)
- ✅ **Issue #3**: QUIC Client Implementation
- ✅ **Issue #4**: Flutter Bridge Validation
- ✅ **Issue #5**: UB in FFI Bridge (OnceCell fix)
- ✅ **Issue #6**: Stream I/O Implementation (Phase 05.1)
- ✅ **Issue #7**: Fingerprint Leakage in Logs

---

## When to Implement

### Phase 07 (Discovery & Auth) - MUST HAVE
- **Token expiry**: Add createdAt/expiresAt to QrPayload, check on load
- **PTY resize on rotation**: Hook didChangeMetrics to resizePty()

### Before Public Release (SHOULD FIX)
- **Silent error handling**: Add logging + connection loss detection
- **Double parsing QR**: Remove FRB parse, use Dart model only
- **Generic error messages**: Add host:port context
- **IP Ban Persistence**: Recommended nếu deploy cho public users
- **Integration Tests**: Recommended nếu có multiple contributors
- **Basic QR validation**: Add IP/port/fingerprint format checks
- **Constant-time comparison**: Nice-to-have security hardening

### Can Defer Indefinitely
- **Hardcoded timeout**: 10s works for most cases

---

## Unresolved Questions

### From MVP (Phase 01-03)
1. **IP Ban Format**: JSON đủ hay cần SQLite?
2. **Ban Duration**: 1h default, hay configurable via flag?
3. **Integration Test Priority**: Manual testing đủ tốt cho MVP?

### From Phase 04/04.1 (QUIC Client)
4. ~~**Stream I/O Implementation**: When will `receive_event()` and `send_command()` be implemented?~~
   - ✅ **RESOLVED**: Implemented in Phase 06
5. ~~**Static Mutable UB**: Why was `unsafe static mut` chosen in `api.rs`?~~
   - ✅ **RESOLVED**: Fixed with `once_cell::sync::OnceCell`
6. ~~**Fingerprint Logging**: Should actual fingerprint be logged in debug mode?~~
   - ✅ **RESOLVED**: Only match result logged, error shows partial (8 chars)
7. **Timeout Configuration**: Should 10s timeout be configurable for different networks?
   - Start with const, make field if needed in Phase 05

### From Phase 06 (Flutter UI)
8. **Token lifecycle**: Token có expiry date không? Nếu có, server gửi trong QR payload không?
9. **Fingerprint revocation**: Nếu fingerprint bị compromise, có cách nào để revoke không?
10. **Event polling**: Tại sao dùng polling thay vì stream? FRB có hỗ trợ stream không?
11. **PTY size**: Font size có configurable không? Need accurate PTY size calculation.
12. **Error handling**: Backend có send specific error codes không? For better error messages.
13. **Connection limits**: Có limit số concurrent connections không? Need để handle connection pool.

---

**Last updated**: 2026-01-08 (Post-Phase 05.1 - Terminal Streaming Integration)
**Next review**: Trước khi implement Phase 07
**Completed plans**:
- `plans/260107-1553-solve-quinn-quic-client/plan.md` (QUIC Client)
- `plans/260107-1648-fix-critical-ub-fingerprint-leak/plan.md` (Bugfix)
- `plans/260106-2127-comacode-mvp/phase-06-flutter-ui.md` (Flutter UI)
- `plans/260108-0907-phase-051-terminal-integration/plan.md` (Terminal Streaming)
