# Brainstorming: Phase 04 (Mobile App) - Revised Plan Review

**Date**: 2026-01-07
**Context**: User review Phase 04 plan, identified missing pieces
**Decision**: Approve revised plan with additions

---

## User Feedback Summary

### Missing Pieces Identified
1. **QR Code Scanner**: Backend generates QR, but client can't scan
2. **Client-side Persistence**: TOFU requires client to store credentials

### Additions Approved
| Component | Purpose | Priority |
|-----------|---------|----------|
| `mobile_scanner` | QR scanning for pairing | Critical |
| `flutter_secure_storage` | Store token/fingerprint | Security |
| Virtual Key Bar | ESC/CTRL for terminal | UX must-have |
| `wakelock_plus` | Keep screen on | Practical |

---

## Technical Analysis

### 1. QR Format ✅ READY

**Backend** (`crates/core/src/types/qr.rs`):
```rust
pub fn to_json(&self) -> Result<String>
pub fn from_json(json: &str) -> Result<Self>
```

**Format**:
```json
{"ip":"192.168.1.1","port":8443,"fingerprint":"AA:BB:CC","token":"deadbeef","protocol_version":1}
```

**Verdict**: ✅ No action needed. Flutter can parse directly.

### 2. Bridge API ❌ MISSING

**Flutter expects**:
```dart
_api.connectToHost(host, port, authToken, serverFingerprint)
```

**Rust现状** (`crates/mobile_bridge/src/api.rs`):
- ❌ No `connectToHost()` function
- ✅ Has encode/decode functions
- ❌ No QUIC client implementation

**Gap**: Need to implement full QUIC client in Rust.

**Estimate**: 8-12h

### 3. TOFU Flow ✅ AGREED

**User choice**: Auto-trust
- Connect success → Save immediately
- No fingerprint verification UI
- Simpler flow for MVP

---

## Implementation Plan

### Phase 04-A: Rust QUIC Client (8-12h)

**File**: `crates/mobile_bridge/src/quic_client.rs`

```rust
use quinn::{Endpoint, ClientConfig};
use comacode_core::QrPayload;

pub struct QuicClient {
    endpoint: Endpoint,
}

impl QuicClient {
    pub async fn connect_to_host(
        &self,
        host: &str,
        port: u16,
        auth_token: &str,
        server_fingerprint: &str,
    ) -> Result<Session, CoreError> {
        // 1. Verify fingerprint (TOFU)
        // 2. Connect to QUIC endpoint
        // 3. Send Hello with auth token
        // 4. Return session handle
    }
}
```

### Phase 04-B: Flutter UI (4-6h)

1. **QR Scanner** (2h)
   - `mobile_scanner` integration
   - Parse QrPayload JSON
   - Camera permission handling

2. **Secure Storage** (1h)
   - `flutter_secure_storage` wrapper
   - Save/load credentials

3. **Connection Provider** (1h)
   - State management
   - Auto-trust flow

4. **Terminal UI** (2h)
   - xterm_flutter integration
   - Virtual key bar (ESC, CTRL, TAB, Arrows)

---

## Dependencies Added

```yaml
# pubspec.yaml
dependencies:
  xterm_flutter: ^2.0.0
  flutter_rust_bridge: ^1.80
  mobile_scanner: ^3.5.0         # NEW
  flutter_secure_storage: ^9.0.0  # NEW
  permission_handler: ^11.0.0     # NEW
  wakelock_plus: ^1.1.0           # NEW
```

**Platform config**:
- iOS: `Info.plist` (NSCameraUsageDescription)
- Android: `AndroidManifest.xml` (CAMERA permission)

---

## Updated Architecture

```
mobile/
├── lib/
│   ├── core/
│   │   └── storage.dart           # NEW: Secure storage
│   ├── features/
│   │   ├── connection/
│   │   │   ├── scan_qr_page.dart  # NEW: QR scanner
│   │   │   ├── manual_connect_page.dart
│   │   │   └── connection_provider.dart
│   │   └── terminal/
│   │       ├── terminal_page.dart
│   │       └── virtual_key_bar.dart  # NEW: ESC/CTRL
│   └── bridge/
│       └── bridge.dart
```

---

## Success Criteria

1. ✅ App scans QR from Host Agent
2. ✅ App connects and verifies fingerprint (auto-trust)
3. ✅ Credentials persist for auto-reconnect
4. ✅ Terminal supports special keys (CTRL-C, ESC)
5. ✅ Screen stays on during session

---

## Unresolved Questions

1. **Connection error handling**: What if QUIC connection fails? Show error or retry silently?

2. **Multiple hosts**: Support multiple saved hosts or just last one?

3. **Token refresh**: When token expires (7 days), force re-scan QR?

---

## Action Items

| Priority | Task | Estimate |
|----------|------|----------|
| P0 | Implement QUIC client in Rust | 8-12h |
| P0 | QR Scanner in Flutter | 2h |
| P1 | Secure Storage wrapper | 1h |
| P1 | Virtual Key Bar | 1h |
| P2 | Multiple hosts support | 2h |

---

## Files to Create/Modify

**Rust**:
- `crates/mobile_bridge/src/quic_client.rs` ← NEW
- `crates/mobile_bridge/src/api.rs` ← Add `connectToHost()`

**Flutter**:
- `mobile/lib/core/storage.dart` ← NEW
- `mobile/lib/features/connection/scan_qr_page.dart` ← NEW
- `mobile/lib/features/terminal/virtual_key_bar.dart` ← NEW

---

**Status**: ✅ Revised plan approved, QUIC client identified as blocker
**Last updated**: 2026-01-07
**Total estimate**: 12-18h (Rust 8-12h + Flutter 4-6h)
