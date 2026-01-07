---
title: "Phase 06: Service Discovery & Authentication"
description: "mDNS discovery and secure authentication for zero-config setup"
status: pending
priority: P1
effort: 6h
branch: main
tags: [mdns, authentication, ux, discovery]
created: 2026-01-06
---

# Phase 06: Service Discovery & Authentication

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 05](./phase-05-network-protocol.md)

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

### Step 1: mDNS Host Advertisement (1.5h)
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

### Step 2: mDNS Client Browser (1.5h)
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

### Step 3: Simple Authentication (1.5h)
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

### Step 4: QR Code Pairing (1h)
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

### Step 5: Credential Storage (0.5h)
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
