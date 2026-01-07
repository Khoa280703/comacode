---
title: "Phase 04: Mobile App (Flutter) - REVISED"
description: "iOS/Android app with terminal UI, QR scanner, secure storage, connects via QUIC"
status: pending
priority: P0
effort: 20h
branch: main
tags: [flutter, ui, terminal, quic-client, qr-scanner]
created: 2026-01-06
updated: 2026-01-07
---

# Phase 04: Mobile App (Flutter) - REVISED

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 03](./phase-03-host-agent.md), [Phase 04 Backend](../260107-0858-brainstorm-implementation/phase-04-cert-persistence.md)
- **Revised**: 2026-01-07 - Added QR scanner, secure storage, virtual key bar, StreamSink streaming

## Overview
Build Flutter mobile app with terminal UI, QR code scanner for pairing, secure credential storage, and QUIC client via Rust FFI.

## Key Insights
- `xterm_flutter` for terminal emulation
- `mobile_scanner` for QR code pairing (matches Backend QR output)
- `flutter_secure_storage` for TOFU credential persistence
- `wakelock_plus` to keep screen on during long sessions
- **Virtual Key Bar**: Mobile keyboards lack ESC/CTRL - critical for vim/nano
- Auto-trust TOFU flow: Connect success → Save credentials immediately

## Revised Requirements
- Terminal UI with xterm_flutter
- **QR Code Scanner** for host pairing
- **Secure Storage** for token/fingerprint (TOFU)
- QUIC client (via Rust FFI) ← **BLOCKER - needs implementation**
- Connection state management
- **Virtual Key Bar** (ESC, CTRL, TAB, Arrows)
- **Keep screen on** during session
- Session persistence (auto-reconnect)
- Camera permissions (iOS/Android)

## Architecture
```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── theme.dart        # Catppuccin colors
│   │   └── storage.dart      # NEW: Secure storage wrapper
│   ├── features/
│   │   ├── terminal/
│   │   │   ├── terminal_page.dart
│   │   │   ├── terminal_widget.dart
│   │   │   └── virtual_key_bar.dart  # NEW: ESC/CTRL keys
│   │   └── connection/
│   │       ├── scan_qr_page.dart      # NEW: QR Scanner
│   │       ├── manual_connect_page.dart
│   │       └── connection_provider.dart
│   └── bridge/
│       ├── bridge_generated.dart
│       └── bridge.dart
├── ios/
│   └── Runner/Info.plist     # Camera permission
└── android/
    └── app/src/main/AndroidManifest.xml  # Camera permission
```

## Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0
  xterm_flutter: ^2.0.0
  flutter_rust_bridge: ^1.80
  mobile_scanner: ^3.5.0         # NEW: QR Code Scanning
  flutter_secure_storage: ^9.0.0  # NEW: Store Token/Fingerprint
  permission_handler: ^11.0.0     # NEW: Camera permission
  wakelock_plus: ^1.1.0           # NEW: Keep screen on
```

## Implementation Steps

### Step 1: Project Setup & Theme (2h)

**Tasks**:
- [ ] `flutter create comacode`
- [ ] Add all dependencies
- [ ] Define Catppuccin Mocha color palette
- [ ] Configure iOS camera permission (`Info.plist`)
- [ ] Configure Android camera permission (`AndroidManifest.xml`)

```dart
// lib/core/theme.dart
class CatppuccinMocha {
  static const base = Color(0xFF1E1E2E);
  static const surface = Color(0xFF313244);
  static const primary = Color(0xFFCBA6F7);
  static const text = Color(0xFFCDD6F4);
  static const green = Color(0xFFA6E3A1);
  static const red = Color(0xFFF38BA8);
  // ...
}
```

### Step 2: Rust QUIC Client (8-12h) ← **BLOCKER**

**Location**: `crates/mobile_bridge/src/`

**Problem**: Current bridge chỉ có encode/decode. Need QUIC client with streaming.

**Required API**:
```rust
// crates/mobile_bridge/src/api.rs
use flutter_rust_bridge::frb;
use flutter_rust_bridge::StreamSink;
use comacode_core::TerminalEvent;

/// Connect to host and stream terminal output to UI
#[frb]
pub fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
    sink: StreamSink<TerminalEvent>,  // ← Push events to Flutter UI continuously
) -> Result<(), String> {
    // 1. Create QUIC endpoint
    // 2. Verify fingerprint (auto-trust)
    // 3. Connect with auth token
    // 4. Spawn background task: read PTY output → sink.add(event)
    // 5. Return immediately (async streaming)
}
```

**Why StreamSink?**
- Terminal output is **continuous stream**, not one-time response
- Flutter needs to receive output line-by-line in real-time
- `StreamSink` is the correct FRB pattern for Rust→Dart streaming

**Tasks**:
- [ ] Implement `QuicClient` struct (using quinn)
- [ ] Add `connectToHost()` with `StreamSink<TerminalEvent>` parameter
- [ ] Handle certificate fingerprint verification
- [ ] Spawn background task to stream PTY output via sink
- [ ] Generate FRB bindings
- [ ] Test streaming with large output

### Step 3: Secure Storage (1h)

```dart
// lib/core/storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class AppStorage {
  static const _storage = FlutterSecureStorage();

  /// Save verified host (TOFU - auto-trust)
  static Future<void> saveHost(QrPayload payload) async {
    final jsonStr = jsonEncode(payload.toJson());
    await _storage.write(
      key: 'host_${payload.fingerprint}',
      value: jsonStr,
    );
    // Mark as last used
    await _storage.write(key: 'last_host', value: payload.fingerprint);
  }

  /// Get last connected host
  static Future<QrPayload?> getLastHost() async {
    final fp = await _storage.read(key: 'last_host');
    if (fp == null) return null;
    final jsonStr = await _storage.read(key: 'host_$fp');
    if (jsonStr == null) return null;
    return QrPayload.fromJson(jsonDecode(jsonStr));
  }

  /// Clear all saved hosts
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
```

**Tasks**:
- [ ] Create `AppStorage` wrapper
- [ ] Implement `saveHost()` for TOFU
- [ ] Implement `getLastHost()` for auto-reconnect
- [ ] Test secure storage on iOS + Android

### Step 4: QR Scanner & Pairing (3h)

```dart
// lib/features/connection/scan_qr_page.dart
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanQrPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scan Host QR')),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            if (barcode.rawValue != null) {
              _handleQrCode(context, barcode.rawValue!);
            }
          }
        },
      ),
    );
  }

  void _handleQrCode(BuildContext context, String rawJson) {
    try {
      final payload = QrPayload.fromJson(jsonDecode(rawJson));
      context.read<ConnectionProvider>().connectWithPayload(payload);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid QR code')),
      );
    }
  }
}
```

**Backend QR format** (already implemented):
```json
{"ip":"192.168.1.1","port":8443,"fingerprint":"AA:BB:CC","token":"deadbeef","protocol_version":1}
```

**Tasks**:
- [ ] Create `QrPayload` model in Dart (match Rust struct)
- [ ] Implement scanner UI
- [ ] Handle camera permissions gracefully
- [ ] Parse and validate QR JSON
- [ ] Auto-connect on scan

### Step 5: Connection Provider (2h)

```dart
// lib/features/connection/connection_provider.dart
class ConnectionState extends ChangeNotifier {
  bool _isConnected = false;
  QrPayload? _currentHost;
  String? _error;

  bool get isConnected => _isConnected;
  String? get error => _error;

  /// Connect using scanned/saved payload (auto-trust TOFU)
  Future<void> connectWithPayload(QrPayload payload) async {
    try {
      setLoading(true);
      _error = null;
      notifyListeners();

      // 1. Call Rust Bridge
      await ComacodeBridge.connect(
        host: payload.ip,
        port: payload.port,
        token: payload.token,
        fingerprint: payload.fingerprint,
      );

      // 2. If successful, persist credentials (TOFU)
      await AppStorage.saveHost(payload);

      _isConnected = true;
      _currentHost = payload;
      WakelockPlus.enable(); // Keep screen on
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
    } finally {
      setLoading(false);
      notifyListeners();
    }
  }

  /// Auto-reconnect to last host
  Future<void> reconnectLast() async {
    final last = await AppStorage.getLastHost();
    if (last != null) {
      await connectWithPayload(last);
    }
  }

  void disconnect() {
    _isConnected = false;
    WakelockPlus.disable();
    notifyListeners();
  }
}
```

**Tasks**:
- [ ] Implement `connectWithPayload()` with auto-trust
- [ ] Implement `reconnectLast()` for auto-reconnect
- [ ] Add loading/error states
- [ ] Enable wakelock on connect
- [ ] Handle disconnect gracefully

### Step 6: Terminal UI + Virtual Key Bar (4h)

```dart
// lib/features/terminal/virtual_key_bar.dart
class VirtualKeyBar extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onToggleKeyboard;  // NEW: Toggle system keyboard
  final VoidCallback onToggleWakelock;  // NEW: Toggle screen lock

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      child: Row(
        children: [
          // Special keys
          _buildKey('ESC', onPressed: () => onKeyPressed('\x1b')),
          _buildKey('CTRL', onPressed: () => _toggleCtrl()),
          _buildKey('TAB', onPressed: () => onKeyPressed('\t')),
          _buildKey('↑', onPressed: () => onKeyPressed('\x1b[A')),
          _buildKey('↓', onPressed: () => onKeyPressed('\x1b[B')),
          _buildKey('←', onPressed: () => onKeyPressed('\x1b[D')),
          _buildKey('→', onPressed: () => onKeyPressed('\x1b[C')),

          Spacer(),

          // NEW: Toggle controls (right side)
          IconButton(
            icon: Icon(Icons.keyboard),
            onPressed: onToggleKeyboard,
            tooltip: 'Toggle keyboard',
          ),
          IconButton(
            icon: Icon(Icons.lock_outline),
            onPressed: onToggleWakelock,
            tooltip: 'Toggle wakelock',
          ),
        ],
      ),
    );
  }
}
```

**Why keyboard toggle?**
- Virtual keyboard covers 1/3 of screen → hard to read logs
- User wants full screen terminal view
- Toggle to hide/show system keyboard on demand

**Tasks**:
- [ ] Integrate xterm_flutter widget
- [ ] Create virtual key bar with ESC/CTRL/TAB/Arrows
- [ ] Add keyboard toggle button (right side)
- [ ] Add wakelock toggle button (right side)
- [ ] Handle keyboard input forwarding
- [ ] Configure `resizeToAvoidBottomInset` properly
- [ ] Catppuccin theme for terminal
- [ ] Test with vim/nano workflows

## Updated Todo List

### Rust (BLOCKER - 8-12h)
- [ ] Implement `QuicClient` struct
- [ ] Add `connectToHost()` with `StreamSink<TerminalEvent>` parameter
- [ ] Handle fingerprint verification
- [ ] Spawn background task to stream PTY output via sink
- [ ] Generate FRB bindings
- [ ] Test streaming with large output

### Flutter (10-12h)
- [ ] Create Flutter project
- [ ] Add all dependencies
- [ ] Configure camera permissions
- [ ] Define Catppuccin theme
- [ ] Implement `AppStorage` wrapper
- [ ] Create `QrPayload` model
- [ ] Build QR scanner page
- [ ] Build connection provider
- [ ] Build terminal widget
- [ ] Build virtual key bar with keyboard/wakelock toggles
- [ ] Test on iOS + Android

## Success Criteria
- [ ] App scans QR code from Host Agent
- [ ] App connects and verifies fingerprint (auto-trust)
- [ ] Credentials persist for auto-reconnect
- [ ] Terminal output streams continuously (StreamSink)
- [ ] Terminal renders in Catppuccin theme
- [ ] Virtual key bar works (ESC, CTRL, Arrows)
- [ ] Keyboard toggle button works (full screen view)
- [ ] Wakelock toggle button works
- [ ] Screen stays on during session
- [ ] App runs on iOS and Android

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| QUIC client not implemented | **100%** | **Blocker** | Implement in Rust first |
| Camera permission denied | Medium | Medium | Fallback to manual entry |
| Secure storage fails | Low | Medium | Fallback to shared_prefs |
| Virtual key bar UX | Low | Low | Iterate based on testing |
| xterm_flutter performance | Medium | High | Test with large output |

## Security Considerations
- ✅ Auto-trust TOFU (user reviewed: acceptable for MVP)
- ✅ Secure storage for tokens
- ✅ Certificate fingerprint verification
- ⚠️ Manual IP entry as fallback (less secure)

## Related Code Files
- `/mobile/lib/main.dart` - App entry
- `/mobile/lib/core/storage.dart` - Secure storage (NEW)
- `/mobile/lib/features/connection/scan_qr_page.dart` - QR scanner (NEW)
- `/mobile/lib/features/terminal/virtual_key_bar.dart` - Virtual keys (NEW)
- `/crates/mobile_bridge/src/quic_client.rs` - QUIC client (TODO)
- `/crates/core/src/types/qr.rs` - QrPayload JSON format (✅ READY)

## Blockers
| Item | Status | Action |
|------|--------|--------|
| QUIC client in Rust | ❌ Missing | **Must implement first** |
| QR format | ✅ Ready | Use `QrPayload::to_json()` |

## Next Steps
1. **Implement QUIC client** in Rust (8-12h) - BLOCKER
2. Generate FRB bindings
3. Build Flutter UI with QR scanner
4. Test end-to-end flow

## Resources
- [xterm_flutter examples](https://pub.dev/packages/xterm_flutter)
- [mobile_scanner docs](https://pub.dev/packages/mobile_scanner)
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- [wakelock_plus](https://pub.dev/packages/wakelock_plus)
- [Backend QR format](../../../../crates/core/src/types/qr.rs)

## See Also
- [Brainstorm Report](../../reports/brainstorming-260107-1450-phase04-mobile-revised.md)
- [Known Issues](./known-issues-technical-debt.md) - QUIC client tracker
