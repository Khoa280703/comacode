---
title: "Phase 07: mDNS Service Discovery"
description: "mDNS auto-discovery for zero-config host detection"
status: in-progress
priority: P1
effort: 4-6h
branch: main
tags: [mdns, discovery, zero-config, ux]
created: 2026-01-06
updated: 2026-01-08
---

# Phase 07: Service Discovery & Authentication

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 06 - Flutter UI](./phase-06-flutter-ui.md) (to be created)
- Next: [Phase 08 - Production Hardening](./phase-07-production-hardening.md) (to be renamed from phase-07)

**Note:** This file was originally `phase-06-discovery-auth.md`, renamed to `phase-07` on 2026-01-07 to reflect updated roadmap.

## Overview
Implement mDNS service discovery for automatic host detection and simple authentication for secure connections.

## Key Insights
- mDNS enables "plug and play" UX
- QR code pairing beats manual IP entry
- Simple password for MVP (PKI in Phase 2)
- Bluetooth LE as fallback for discovery
- Stored credentials for reconnection

## Requirements
- mDNS advertisement (host)
- mDNS browsing (client)
- Simple password authentication
- QR code pairing option
- Credential storage (secure)
- Connection history
- Bluetooth LE discovery (fallback)

## Architecture
```
Discovery Layer
├── mDNS Service
│   ├── Host Advertisement
│   └── Client Browser
├── Authentication
│   ├── Password Exchange
│   └── Session Token
└── Fallback
    ├── QR Code
    └── Bluetooth LE
```

## Implementation Steps

### Step 1: Token Expiry Mechanism (1h) **[From Phase 06 Debt]
```dart
// mobile/lib/core/storage.dart
class QrPayload {
  final String ip;
  final int port;
  final String fingerprint;
  final String token;
  final DateTime createdAt;      // ✅ Thêm timestamp
  final DateTime? expiresAt;     // ✅ Thêm expiry (default 24h)

  factory QrPayload.fromJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return QrPayload(
      // ... existing fields
      createdAt: DateTime.parse(decoded['created_at']),
      expiresAt: decoded['expiresAt'] != null
          ? DateTime.parse(decoded['expiresAt'])
          : null,
    );
  }
}

// Check expiry when loading
static Future<QrPayload?> getLastHost() async {
  final payload = QrPayload.fromJson(jsonStr);

  // Auto-revoke expired tokens
  if (payload.expiresAt != null && DateTime.now().isAfter(payload.expiresAt!)) {
    await deleteHost(fp);
    return null;
  }

  return payload;
}
```

**Tasks**:
- [ ] Add `createdAt` and `expiresAt` to QrPayload model
- [ ] Set default expiry to 24 hours from QR generation
- [ ] Check expiry on load from storage
- [ ] Auto-delete expired credentials
- [ ] Update QR payload format on host side

### Step 2: PTY Resize on Screen Rotation (1.5h) **[From Phase 06 Debt]
```dart
// mobile/lib/features/terminal/terminal_page.dart
class _TerminalWidgetState extends ConsumerState<TerminalWidget> {
  int _terminalRows = 24;
  int _terminalCols = 80;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTerminalSize();
  }

  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateTerminalSize();
  }

  void _updateTerminalSize() {
    final screenSize = MediaQuery.of(context).size;
    const charWidth = 7.5;   // monospace font width
    const charHeight = 16.0;  // monospace font height

    final newCols = (screenSize.width / charWidth).floor();
    final newRows = (screenSize.height / charHeight).floor();

    if (newCols != _terminalCols || newRows != _terminalRows) {
      _terminalCols = newCols;
      _terminalRows = newRows;
      bridge.resizePty(rows: _terminalRows, cols: _terminalCols);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
```

**Tasks**:
- [ ] Add `didChangeMetrics()` observer
- [ ] Calculate terminal size from screen dimensions
- [ ] Call `resizePty()` when size changes
- [ ] Add observer lifecycle management
- [ ] Test on device rotation

### Step 3: mDNS Host Advertisement (1.5h)
```rust
// crates/host_agent/src/mdns.rs
use mdns_sd::{ServiceDaemon, ServiceInfo};

pub async fn advertise_mdns(port: u16, hostname: String) -> Result<()> {
    let mdns = ServiceDaemon::new()?;

    let service = ServiceInfo::new(
        "_comacode._tcp.local.",,
        &hostname,
        "",
        port,
        None,
    )?;

    mdns.register(service)?;

    Ok(())
}
```

**Tasks**:
- [ ] Add `mdns-sd` dependency
- [ ] Advertise service on `_comacode._tcp`
- [ ] Include hostname in TXT record
- [ ] Auto-refresh registration
- [ ] Handle mDNS errors gracefully

### Step 4: mDNS Client Browser (1.5h)
```dart
// mobile/lib/features/discovery/mdns_browser.dart
import 'package:mdns/mdns.dart';

class MdnsBrowser {
  final controller = StreamController<HostDiscovery>();

  Future<void> startBrowsing() async {
    final browser = MdnsBrowser.lookup('_comacode._tcp');

    await for (final MdnsResponse response in browser) {
      controller.add(HostDiscovery(
        name: response.name,
        host: response.host,
        port: response.port,
      ));
    }
  }
}
```

**Tasks**:
- [ ] Add `mdns` Flutter plugin
- [ ] Browse for `_comacode._tcp` services
- [ ] Parse service responses
- [ ] Update UI with discovered hosts
- [ ] Handle timeout/cleanup

### Step 5: Simple Authentication (1.5h)
```rust
// crates/core/src/auth.rs
use sha2::{Sha256, Digest};

pub struct AuthChallenge {
    pub nonce: [u8; 32],
    pub timestamp: u64,
}

pub fn verify_password(challenge: &AuthChallenge, response: &[u8], password: &str) -> bool {
    let mut hasher = Sha256::new();
    hasher.update(&challenge.nonce);
    hasher.update(password.as_bytes());
    let expected = hasher.finalize();

    response == expected.as_slice()
}

pub fn generate_response(challenge: &AuthChallenge, password: &str) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(&challenge.nonce);
    hasher.update(password.as_bytes());
    hasher.finalize().to_vec()
}
```

**Tasks**:
- [ ] Implement challenge-response protocol
- [ ] Add SHA-256 hashing
- [ ] Generate nonce for each auth
- [ ] Timestamp for replay prevention
- [ ] Password storage in keychain

### Step 6: QR Code Pairing (1h)
```dart
// mobile/lib/features/discovery/qr_pairing.dart
import 'package:qr_code_scanner/qr_code_scanner.dart';

class QrPairingPage extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return QRView(
      key: qrKey,
      onQRViewCreated: (controller) {
        controller.scannedDataStream.listen((scanData) {
          final code = scanData.code;
          // Parse: comacode://192.168.1.100:8443?token=xyz
          _handleConnection(code);
        });
      },
    );
  }
}
```

**Tasks**:
- [ ] Generate QR on host (URL + token)
- [ ] Scan QR in mobile app
- [ ] Parse connection details
- [ ] Extract auth token
- [ ] Trigger connection

### Step 7: Credential Storage (0.5h)
```dart
// mobile/lib/core/storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  final _storage = FlutterSecureStorage();

  Future<void> savePassword(String host, String password) {
    return _storage.write(key: 'pwd_$host', value: password);
  }

  Future<String?> getPassword(String host) {
    return _storage.read(key: 'pwd_$host');
  }
}
```

**Tasks**:
- [ ] Add `flutter_secure_storage`
- [ ] Store passwords per host
- [ ] iOS: Use Keychain
- [ ] Android: Use Keystore
- [ ] Clear on logout

## Todo List

### From Phase 06 Debt (High Priority)
- [ ] **Token expiry mechanism**: Add createdAt/expiresAt to QrPayload
- [ ] **PTY resize on rotation**: Hook didChangeMetrics to resizePty()

### Phase 07 Core Tasks
- [ ] Add mDNS dependencies
- [ ] Implement host advertisement
- [ ] Build mDNS browser
- [ ] Create auth protocol
- [ ] Add password hashing
- [ ] Implement QR pairing
- [ ] Secure credential storage
- [ ] Add connection history
- [ ] Test on real networks
- [ ] UX polish

## Success Criteria
- Host appears in mobile app automatically
- Connection <10s after opening app
- Password auth prevents unauthorized access
- QR code pairing works as fallback
- Credentials stored securely
- Reconnection works without re-auth

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| mDNS blocked by network | Medium | High | QR fallback + manual IP |
| Android mDNS permissions | Medium | Medium | Request at runtime, fallback |
| Weak passwords (MVP) | High | Low | Document security model |
| Keychain access fail | Low | Low | Clear credentials, re-auth |

## Security Considerations
- **MVP**: Simple password (acceptable for LAN)
- **Phase 2**: Public key auth, TLS cert pinning
- Nonces prevent replay attacks
- Secure storage for credentials
- Password never sent plaintext

## Related Code Files
- `/crates/host_agent/src/mdns.rs` - Host discovery
- `/crates/core/src/auth.rs` - Authentication logic
- `/mobile/lib/features/discovery/` - Discovery UI

## Next Steps
After discovery works, proceed to [Phase 07: Testing & Deploy](./phase-07-testing-deploy.md) for final polish.

## Resources
- [mdns-sd docs](https://docs.rs/mdns-sd/)
- [Flutter mDNS plugin](https://pub.dev/packages/mdns)
- [QR scanner](https://pub.dev/packages/qr_code_scanner)
- [Secure storage](https://pub.dev/packages/flutter_secure_storage)
