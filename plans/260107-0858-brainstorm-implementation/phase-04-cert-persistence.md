---
title: "Phase 04: Certificate Persistence + TOFU"
description: "Persist cert/key với dirs crate, QR code generation, TOFU verification"
status: pending
priority: P0
effort: 5h
phase: 04
created: 2026-01-07
---

## Objectives

Implement certificate persistence để avoid repeated pairing, và TOFU (Trust On First Use) workflow với QR code scanning.

## Tasks

### 4.1 Add Dependencies (15min)

**File**: `Cargo.toml`

```toml
[workspace.dependencies]
# File system paths
dirs = "5.0"
# QR code generation
qrcode = "0.14"
# SHA-256 for fingerprint
sha2 = "0.10"
# JSON serialization (already in workspace)
serde_json = "1.0"
```

### 4.2 Certificate Persistence (2h)

**File**: `crates/hostagent/src/cert.rs` (new)

```rust
use quinn::crypto::rustls::Certificate;
use std::fs;
use std::path::PathBuf;

pub struct CertStore {
    data_dir: PathBuf,
}

impl CertStore {
    /// Initialize certificate store
    pub fn new() -> Result<Self, CoreError> {
        let data_dir = dirs::data_local_dir()
            .ok_or(CoreError::NoDataDir)?
            .join("comacode");

        // Create directory if not exists
        fs::create_dir_all(&data_dir)?;

        Ok(Self { data_dir })
    }

    /// Path to certificate file
    fn cert_path(&self) -> PathBuf {
        self.data_dir.join("host.crt")
    }

    /// Path to private key file
    fn key_path(&self) -> PathBuf {
        self.data_dir.join("host.key")
    }

    /// Load existing certificate pair
    pub fn load(&self) -> Result<Option<(Certificate, Vec<u8>)>, CoreError> {
        let cert_path = self.cert_path();
        let key_path = self.key_path();

        if !cert_path.exists() || !key_path.exists() {
            return Ok(None);
        }

        let cert_bytes = fs::read(&cert_path)?;
        let key_bytes = fs::read(&key_path)?;

        // Parse certificate
        let cert = Certificate::from_der(&cert_bytes)
            .map_err(|e| CoreError::CertParseError(e.to_string()))?;

        Ok(Some((cert, key_bytes)))
    }

    /// Save new certificate pair
    pub fn save(&self, cert: &Certificate, key: &[u8]) -> Result<(), CoreError> {
        fs::write(self.cert_path(), cert.as_ref())?;
        fs::write(self.key_path(), key)?;

        // Set permissions (read-only by owner)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perm = fs::metadata(self.key_path())?.permissions();
            perm.set_mode(0o600);  // rw-------
            fs::set_permissions(self.key_path(), perm)?;
        }

        Ok(())
    }

    /// Clear stored certificates (for testing/reset)
    pub fn clear(&self) -> Result<(), CoreError> {
        let _ = fs::remove_file(self.cert_path());
        let _ = fs::remove_file(self.key_path());
        Ok(())
    }
}
```

### 4.3 Certificate Fingerprint (1h)

**File**: `crates/hostagent/src/cert.rs`

```rust
use sha2::{Sha256, Digest};

impl CertStore {
    /// Get certificate fingerprint (SHA-256)
    pub fn fingerprint(&self, cert: &Certificate) -> String {
        let der = cert.as_ref();
        let hash = Sha256::digest(der);

        // Format as hex
        hash.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<Vec<_>>()
            .join(":")
    }
}
```

**Usage**:
```rust
let cert_store = CertStore::new()?;

if let Some((cert, key)) = cert_store.load()? {
    // Existing cert found
    let fingerprint = cert_store.fingerprint(&cert);
    tracing::info!("Loaded cert: {}", fingerprint);
} else {
    // Generate new cert
    let (cert, key) = generate_cert_pair()?;
    cert_store.save(&cert, &key)?;
}
```

### 4.4 QR Code Data Structure (30min)

**File**: `crates/core/src/types/qr.rs` (new)

```rust
use serde::{Deserialize, Serialize};

/// QR code payload for pairing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrPayload {
    /// Host IP address
    pub ip: String,

    /// Host port
    pub port: u16,

    /// Certificate fingerprint (SHA-256, hex format)
    pub fingerprint: String,

    /// Auth token (hex format)
    pub token: String,

    /// Protocol version
    pub protocol_version: u32,
}

impl QrPayload {
    /// Serialize to JSON string (for QR encoding)
    pub fn to_json(&self) -> Result<String, CoreError> {
        serde_json::to_string(self)
            .map_err(|e| CoreError::SerializationError(e.to_string()))
    }

    /// Deserialize from JSON string
    pub fn from_json(json: &str) -> Result<Self, CoreError> {
        serde_json::from_str(json)
            .map_err(|e| CoreError::SerializationError(e.to_string()))
    }

    /// Render QR code as Unicode string (for terminal display)
    ///
    /// **IMPORTANT**: Uses Dense1x2 Unicode renderer for terminal.
    /// NOT SVG - SVG will print as garbage XML text.
    pub fn to_qr_terminal(&self) -> Result<String, CoreError> {
        use qrcode::render::unicode;

        let json = self.to_json()?;

        // Generate QR code
        let qr_code = qrcode::QrCode::new(json)
            .map_err(|e| CoreError::QrGenerationError(e.to_string()))?;

        // Render to Unicode (Dense1x2 = high density, scan-able)
        let image = qr_code.render::<unicode::Dense1x2>()
            .dark_color(unicode::Dense1x2::Light)   // Dark on terminal = Light char
            .light_color(unicode::Dense1x2::Dark)   // Light background = Dark char
            .build();

        Ok(image)
    }
}
```

### 4.5 Hostagent Integration (45min)

**File**: `crates/hostagent/src/main.rs`

```rust
use comacode_core::types::qr::QrPayload;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};

pub async fn start_hostagent() -> Result<(), CoreError> {
    let cert_store = CertStore::new()?;

    // Load or generate cert
    let (cert, key) = match cert_store.load()? {
        Some(pair) => pair,
        None => {
            tracing::info!("Generating new certificate...");
            let pair = generate_cert_pair()?;
            cert_store.save(&pair.0, &pair.1)?;
            pair
        }
    };

    let fingerprint = cert_store.fingerprint(&cert);
    tracing::info!("Certificate fingerprint: {}", fingerprint);

    // Generate auth token
    let token_store = TokenStore::new();
    let token = token_store.generate_token().await;
    tracing::info!("Auth token: {}", token.to_hex());

    // Get host address
    let bind_addr: SocketAddr = "0.0.0.0:0".parse()?;  // OS assigns port
    let listener = bind_quic_listener(bind_addr, &cert, &key).await?;
    let actual_port = listener.local_addr()?.port();
    let local_ip = get_local_ip()?;

    // Create QR payload
    let qr_payload = QrPayload {
        ip: local_ip.to_string(),
        port: actual_port,
        fingerprint,
        token: token.to_hex(),
        protocol_version: PROTOCOL_VERSION,
    };

    // Display QR code (Unicode for terminal scanning)
    println!("============================================");
    println!("Scan QR code to connect:");
    println!("\n{}\n", qr_payload.to_qr_terminal()?);
    println!("============================================");
    println!("IP: {}", qr_payload.ip);
    println!("Port: {}", qr_payload.port);
    println!("Fingerprint: {}", qr_payload.fingerprint);
    println!("============================================");
    println!("TIP: If QR doesn't work, check IP with 'ifconfig' or 'ip addr'");

    // Start accepting connections...
    Ok(())
}

/// Get local IP address for QR code
///
/// **IMPORTANT**: Filters out Docker bridge (172.17.x.x), loopback (127.x.x.x)
/// and prefers 192.168.x.x (typical LAN).
fn get_local_ip() -> Result<IpAddr, CoreError> {
    use std::net::UdpSocket;

    // Create UDP socket to a non-local address (doesn't actually send data)
    let socket = UdpSocket::bind("0.0.0.0:0")
        .map_err(|e| CoreError::NetworkError(e.to_string()))?;

    // Connect to external DNS (doesn't send, just determines local interface)
    socket.connect("8.8.8.8:80")
        .map_err(|e| CoreError::NetworkError(e.to_string()))?;

    let local_ip = socket.local_addr()?.ip();

    // Filter: reject Docker bridge (172.17.x.x), loopback
    match local_ip {
        IpAddr::V4(ipv4) if is_docker_or_loopback(ipv4) => {
            tracing::warn!("Detected Docker/loopback IP {}, falling back to 192.168.1.1", local_ip);
            // Fallback: assume typical LAN (user can override with --ip flag)
            Ok(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1)))
        }
        _ => Ok(local_ip),
    }
}

fn is_docker_or_loopback(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    // Docker bridge: 172.17.x.x
    // Loopback: 127.x.x.x
    octets[0] == 172 && octets[1] == 17
        || octets[0] == 127
}
```

### 4.6 Client-Side TOFU (30min)

**File**: `crates/mobile_bridge/src/tofu.rs` (new)

```rust
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// TOFU store for certificate fingerprint verification
///
/// **IMPORTANT**: This is IN-MEMORY only for MVP.
/// Persistence delegated to Flutter layer (Phase E05) via FFI.
/// Flutter uses SharedPreferences/path_provider to store known_hosts.
pub struct TofuStore {
    known_hosts: Arc<RwLock<HashMap<String, String>>>,  // ip -> fingerprint
}

impl TofuStore {
    pub fn new() -> Self {
        Self {
            known_hosts: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Verify host fingerprint (TOFU logic)
    ///
    /// **First time**: Accepts and stores in memory
    /// **Subsequent**: Verifies fingerprint matches stored
    pub async fn verify(&self, host: &str, fingerprint: &str) -> Result<bool, CoreError> {
        let known = self.known_hosts.read().await;

        match known.get(host) {
            None => {
                // First time seeing this host
                tracing::info!("TOFU: Accepting new host {} with fingerprint {}", host, fingerprint);
                drop(known);
                self.known_hosts.write().await.insert(host.to_string(), fingerprint.to_string());
                Ok(true)
            }
            Some(stored) => {
                // Known host, verify fingerprint
                if stored == fingerprint {
                    Ok(true)
                } else {
                    tracing::warn!("TOFU: Fingerprint mismatch for host {}", host);
                    Err(CoreError::FingerprintMismatch {
                        host: host.to_string(),
                        expected: stored.clone(),
                        got: fingerprint.to_string(),
                    })
                }
            }
        }
    }

    /// Load known hosts from Flutter (via FFI)
    ///
    /// Called by Flutter on app startup to restore persisted fingerprints.
    pub async fn load_from_flutter(&self, hosts: Vec<(String, String)>) {
        let mut known = self.known_hosts.write().await;
        for (host, fingerprint) in hosts {
            known.insert(host, fingerprint);
        }
    }

    /// Clear known hosts (for testing/reset)
    pub async fn clear(&self) {
        self.known_hosts.write().await.clear();
    }
}
```

**Integration in connection**:
```rust
// After receiving Hello
let cert_fingerprint = stream.peer_cert_fingerprint()?;
tofu_store.verify(&host_ip, &cert_fingerprint).await?;
```

**Flutter Integration (Phase E05)**:
```dart
// Flutter side - load from SharedPreferences
Future<void> loadKnownHosts() async {
  final prefs = await SharedPreferences.getInstance();
  final hostsJson = prefs.getString('known_hosts') ?? '{}';

  // Parse and send to Rust via FFI
  final hosts = Map<String, String>.from(jsonDecode(hostsJson));
  tofuStore.loadFromFlutter(hosts.entries.toList());
}
```

## Testing Strategy

**Manual Test**:
1. Start hostagent → displays QR code
2. Scan QR with mobile → extracts IP, port, fingerprint, token
3. Connect → TOFU accepts on first attempt
4. Restart hostagent with different cert → TOFU rejects
5. Clear TOFU store → reconnect succeeds

**Acceptance Criteria**:
- ✅ Cert persists across restarts
- ✅ QR code contains all required fields
- ✅ TOFU accepts new hosts automatically
- ✅ TOFU rejects changed fingerprints
- ✅ Auth token from QR allows connection

## Dependencies

- Phase 01 (Protocol version)
- Phase 03 (Auth token)

## Blocked By

- None

## UX Flow

**First Pairing**:
```
1. Hostagent starts → generates cert + token
2. Displays QR code (IP + Port + Fingerprint + Token)
3. Mobile scans QR → extracts data
4. Mobile connects → TOFU accepts (first time)
5. Connection established
```

**Subsequent Connections**:
```
1. Hostagent starts → loads existing cert
2. Mobile connects with saved token
3. TOFU verifies fingerprint matches
4. Connection established
```

**Fingerprint Change**:
```
1. Hostagent cert changes (regenerated)
2. Mobile connects → TOFU detects mismatch
3. Mobile shows error: "Host fingerprint changed!"
4. User must re-scan QR code to trust new cert
```

## Unresolved Questions

1. **QR code format**: JSON raw hay base64 encoded? → JSON is readable, use that
2. **Token rotation**: Should token change on reconnect? → No, static for MVP
3. **Multiple hosts**: How to handle saved connections? → Store in TofuStore by IP
4. **~~QR display~~**: ~~SVG vs PNG vs ASCII~~ → RESOLVED: Unicode Dense1x2 for terminal
5. **IP detection fallback**: What if 192.168.1.1 is wrong? → Add --ip flag for manual override
