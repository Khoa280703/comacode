# Comacode System Architecture

> Version: 1.0 | Last Updated: 2026-01-07
> Phase: Phase 04 - QUIC Client Implementation

---

## Table of Contents
- [High-Level Architecture](#high-level-architecture)
- [Component Architecture](#component-architecture)
- [Data Flow](#data-flow)
- [Network Protocol](#network-protocol)
- [Security Architecture](#security-architecture)
- [Deployment Architecture](#deployment-architecture)
- [Technology Decisions](#technology-decisions)

---

## High-Level Architecture

### System Overview

Comacode is a **distributed terminal control system** consisting of three main components:

1. **Host Agent** (Rust): Runs on desktop machines, manages PTY and QUIC server
2. **Mobile App** (Flutter + Rust FFI): Runs on iOS/Android, connects to Host Agent
3. **Network Layer** (QUIC/TLS): Secure, low-latency communication protocol

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Mobile Device                              │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Flutter UI Layer                         │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │   │
│  │  │Discovery │  │ Terminal │  │ Settings │  │   QR     │    │   │
│  │  │  Screen  │  │  Screen  │  │  Screen  │  │ Scanner  │    │   │
│  │  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘    │   │
│  │        └───────────────┴───────────────┴───────────────┘     │   │
│  │                           │                                  │   │
│  │  ┌────────────────────────▼──────────────────────────────┐  │   │
│  │  │           ConnectionProvider (State Management)       │  │   │
│  │  │  - Connection lifecycle                              │  │   │
│  │  │  - Credential storage (Keychain/Keystore)            │  │   │
│  │  │  - Error handling                                    │  │   │
│  │  └────────────────────────┬─────────────────────────────┘  │   │
│  │                           │                                  │   │
│  │  ┌────────────────────────▼──────────────────────────────┐  │   │
│  │  │         Flutter Rust Bridge (FRB)                     │  │   │
│  │  │  - Dart ↔ Rust serialization                         │  │   │
│  │  │  - StreamSink for async streaming                    │  │   │
│  │  └────────────────────────┬─────────────────────────────┘  │   │
│  └───────────────────────────┼─────────────────────────────────┘   │
│                              │ FFI Boundary                        │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │                   Rust FFI Bridge Layer                     │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │              QuicClient (Phase 04)                   │   │   │
│  │  │  - connect(): Establish QUIC connection              │   │   │
│  │  │  - receive_event(): Stream TerminalEvent → Flutter   │   │   │
│  │  │  - send_command(): Send user input → Host Agent      │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │              TofuVerifier                            │   │   │
│  │  │  - verify_server_cert(): SHA256 fingerprint check   │   │   │
│  │  │  - normalize_fingerprint(): Case-insensitive compare│   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ QUIC Protocol (TLS 1.3)
                                 │ UDP Port 8443
                                 │
┌────────────────────────────────▼─────────────────────────────────────┐
│                       Desktop Machine (Host Agent)                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   QUIC Server (Quinn)                       │   │
│  │  - Accept incoming connections                             │   │
│  │  - Validate AuthToken                                      │   │
│  │  - Manage connection state                                 │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │                 Certificate Manager                         │   │
│  │  - Generate self-signed certificate on startup             │   │
│  │  - Calculate SHA256 fingerprint                            │   │
│  │  - Generate QR code for pairing                            │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │                   AuthToken Generator                       │   │
│  │  - Generate 256-bit random token on startup                 │   │
│  │  - Validate token on connection                            │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │                    PTY Manager                              │   │
│  │  - Spawn shell process (zsh/bash)                          │   │
│  │  - Read PTY output → TerminalEvent                         │   │
│  │  - Write user input → PTY                                  │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │                      Shell Process                          │   │
│  │  - Execute commands                                        │   │
│  │  - Return output                                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Separation of Concerns**: UI, networking, and business logic are isolated
2. **Async-First**: All I/O operations use async/await for non-blocking behavior
3. **Type Safety**: Strong typing in Rust and Dart prevents entire classes of bugs
4. **Zero-Copy**: Use Postcard serialization and efficient data structures
5. **Mobile-First**: UI optimized for touch, small screens, and battery life

---

## Component Architecture

### Host Agent Components

#### 1. QUIC Server
**File**: `crates/host_agent/src/quic_server.rs`

**Responsibilities**:
- Accept incoming QUIC connections
- Validate AuthToken
- Manage connection lifecycle
- Route data between client and PTY

**Key Methods**:
```rust
pub struct QuicServer {
    endpoint: Endpoint,
    auth_token: AuthToken,
    connections: HashMap<ConnectionId, Connection>,
}

impl QuicServer {
    pub async fn start(&self, addr: SocketAddr) -> Result<()>;
    pub async fn handle_connection(&self, conn: Connection) -> Result<()>;
    pub async fn broadcast_event(&self, event: TerminalEvent);
}
```

#### 2. Certificate Manager
**File**: `crates/host_agent/src/certificate.rs`

**Responsibilities**:
- Generate self-signed certificate on startup
- Calculate SHA256 fingerprint
- Export to QR code format

**Key Methods**:
```rust
pub struct CertificateManager {
    cert: Certificate,
    private_key: PrivateKey,
    fingerprint: String,
}

impl CertificateManager {
    pub fn generate() -> Result<Self>;
    pub fn fingerprint(&self) -> &str;
    pub fn to_qr_payload(&self, token: &AuthToken, addr: SocketAddr) -> QrPayload;
}
```

#### 3. PTY Manager
**File**: `crates/host_agent/src/pty.rs`

**Responsibilities**:
- Spawn shell process (zsh/bash)
- Read PTY output → TerminalEvent
- Write user input → PTY
- Handle window resize

**Key Methods**:
```rust
pub struct PtyManager {
    pty: Box<Pty>,
    shell: Child,
}

impl PtyManager {
    pub fn spawn(shell: &str, rows: u16, cols: u16) -> Result<Self>;
    pub async fn read_output(&mut self) -> Result<TerminalEvent>;
    pub fn write_input(&mut self, input: &str) -> Result<()>;
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()>;
}
```

### Mobile Bridge Components

#### 1. QUIC Client
**File**: `crates/mobile_bridge/src/quic_client.rs`

**Responsibilities**:
- Establish QUIC connection to host
- Verify certificate fingerprint (TOFU)
- Stream TerminalEvent to Flutter
- Send user input to host

**Key Methods**:
```rust
pub struct QuicClient {
    endpoint: Endpoint,
    connection: Option<Connection>,
    server_fingerprint: String,
}

impl QuicClient {
    pub fn new(server_fingerprint: String) -> Self;
    pub async fn connect(&mut self, host: String, port: u16, auth_token: String)
        -> Result<(), String>;
    pub async fn receive_event(&self) -> Result<TerminalEvent, String>;
    pub async fn send_command(&self, command: String) -> Result<(), String>;
    pub async fn disconnect(&mut self) -> Result<(), String>;
}
```

#### 2. TOFU Verifier
**File**: `crates/mobile_bridge/src/quic_client.rs` (embedded)

**Responsibilities**:
- Calculate SHA256 fingerprint of server certificate
- Normalize fingerprints (case-insensitive, separator-agnostic)
- Compare with expected fingerprint

**Key Methods**:
```rust
struct TofuVerifier {
    expected_fingerprint: String,
}

impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(&self, end_entity: &CertificateDer<'_>)
        -> Result<ServerCertVerified, rustls::Error>;
    fn verify_tls12_signature(...) -> Result<HandshakeSignatureValid, rustls::Error>;
    fn verify_tls13_signature(...) -> Result<HandshakeSignatureValid, rustls::Error>;
}

impl TofuVerifier {
    fn normalize_fingerprint(fp: &str) -> String;
    fn calculate_fingerprint(&self, cert: &CertificateDer) -> String;
}
```

#### 3. FFI Bridge
**File**: `crates/mobile_bridge/src/api.rs`

**Responsibilities**:
- Expose Rust functions to Flutter
- Serialize/deserialize data (Dart ↔ Rust)
- Manage StreamSink for async streaming

**Key Functions**:
```rust
#[frb]
pub fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
    sink: StreamSink<TerminalEvent>,
) -> Result<(), String>;

#[frb]
pub fn send_command(command: String) -> Result<(), String>;

#[frb]
pub fn disconnect() -> Result<(), String>;
```

### Mobile App Components

#### 1. Connection Provider
**File**: `mobile/lib/features/connection/connection_provider.dart`

**Responsibilities**:
- Manage connection state (connecting, connected, error)
- Store/retrieve credentials (Keychain/Keystore)
- Notify UI of state changes

**Key Methods**:
```dart
class ConnectionProvider extends ChangeNotifier {
  bool _isConnected = false;
  QrPayload? _currentHost;
  String? _error;

  Future<void> connectWithPayload(QrPayload payload);
  Future<void> reconnectLast();
  void disconnect();
}
```

#### 2. Terminal Widget
**File**: `mobile/lib/features/terminal/terminal_widget.dart`

**Responsibilities**:
- Render terminal output using xterm_flutter
- Handle keyboard input
- Support virtual key bar (ESC, CTRL, Arrows)

**Key Components**:
```dart
class TerminalWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: XtermWidget()),
        VirtualKeyBar(onKeyPressed: _handleKeyPress),
      ],
    );
  }
}

class VirtualKeyBar extends StatelessWidget {
  final Function(String) onKeyPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      child: Row(
        children: [
          _buildKey('ESC', onPressed: () => onKeyPressed('\x1b')),
          _buildKey('CTRL', onPressed: () => _toggleCtrl()),
          // ...
        ],
      ),
    );
  }
}
```

#### 3. QR Scanner
**File**: `mobile/lib/features/connection/scan_qr_page.dart`

**Responsibilities**:
- Scan QR code using camera
- Parse QR JSON payload
- Auto-connect on successful scan

**Key Methods**:
```dart
class ScanQrPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            _handleQrCode(context, barcode.rawValue!);
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
      showError(context, 'Invalid QR code');
    }
  }
}
```

---

## Data Flow

### Connection Establishment Flow

```
┌──────────────┐                              ┌──────────────┐
│ Mobile App   │                              │ Host Agent   │
└──────┬───────┘                              └──────┬───────┘
       │                                             │
  1. User scans QR code                             │
     (IP, port, fingerprint, token)                 │
       │                                             │
  2. connect_to_host()                              │
       │                                             │
  3. QuicClient::connect()                          │
       │                                             │
  4. ──────── QUIC Handshake ──────────────────────>│
       │                                             │
       │                                      5. Accept connection
       │                                      6. Validate AuthToken
       │                                             │
       │<─────── TLS Certificate ───────────────────│
       │                                             │
  7. TofuVerifier::verify_server_cert()             │
       │  - Calculate SHA256 fingerprint            │
       │  - Normalize (case-insensitive)            │
       │  - Compare with expected                   │
       │                                             │
  8. ──────── Auth Token ──────────────────────────>│
       │                                             │
       │                                      9. Validate token
       │                                             │
       │<─────── Connection Accepted ───────────────│
       │                                             │
 10. Save credentials (TOFU)                        │
       │  - Keychain (iOS)                          │
       │  - Keystore (Android)                      │
       │                                             │
 11. Spawn background task:                         │
       │  - Read PTY output → StreamSink            │
       │                                             │
 12. Notify listeners: isConnected = true          │
       │                                             │
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
       │                                             │
     ACTIVE SESSION                                 │
       │                                             │
```

### Terminal Output Flow (PTY → Mobile)

```
┌──────────────┐                              ┌──────────────┐
│ Host Agent   │                              │ Mobile App   │
└──────┬───────┘                              └──────┬───────┘
       │                                             │
  1. Shell process writes output                     │
       │                                             │
  2. PTY Manager reads bytes                         │
       │                                             │
  3. Convert to TerminalEvent::Output(string)        │
       │                                             │
  4. ──────── TerminalEvent (Postcard) ────────────>│
       │                                             │
       │                                      5. Receive via QUIC
       │                                      6. Deserialize
       │                                             │
       │  7. StreamSink::add(TerminalEvent)          │
       │     (Background task → Flutter UI)          │
       │                                             │
  8. xterm_flutter::write(output)                   │
       │                                             │
  9. Render terminal output                          │
       │                                             │
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
       │                                             │
     CONTINUOUS LOOP                                │
       │                                             │
```

### User Input Flow (Mobile → PTY)

```
┌──────────────┐                              ┌──────────────┐
│ Mobile App   │                              │ Host Agent   │
└──────┬───────┘                              └──────┬───────┘
       │                                             │
  1. User types on keyboard/virtual keys             │
       │                                             │
  2. Capture input (string + escape sequences)       │
       │                                             │
  3. ──────── Input String ─────────────────────────>│
       │                                             │
       │                                      4. Receive via QUIC
       │                                      5. Write to PTY
       │                                             │
       │                                      6. PTY forwards to shell
       │                                             │
       │                                      7. Shell executes command
       │                                             │
  8. ──────── Terminal Event (Output) ─────────────<│
       │     (See previous flow)                     │
       │                                             │
```

---

## Network Protocol

### QUIC over TLS 1.3

**Protocol Stack**:
```
┌─────────────────────────────────────┐
│   Application (Terminal Events)    │
├─────────────────────────────────────┤
│   Postcard Serialization            │  ← Binary format, zero-copy
├─────────────────────────────────────┤
│   QUIC Streams (Bidirectional)      │  ← Multiple streams per conn
├─────────────────────────────────────┤
│   TLS 1.3 (Encryption)              │  ← Forward secrecy
├─────────────────────────────────────┤
│   QUIC (Transport)                  │  ← UDP-based
├─────────────────────────────────────┤
│   UDP (Network)                     │  ← Port 8443
└─────────────────────────────────────┘
```

### Message Format

**TerminalEvent** (Postcard serialized):
```rust
pub enum TerminalEvent {
    Output { data: Vec<u8> },           // PTY output
    Error { message: String },          // Error message
    Resize { rows: u16, cols: u16 },    // Window resize
    Close,                              // Connection closed
}

// Serialized size: ~8-1024 bytes (depending on output)
```

**User Input** (Plain string):
```rust
// User input (including escape sequences)
pub struct UserInput {
    pub data: String,  // Raw input (e.g., "ls\n", "\x1b[A" for arrow up)
}

// Example inputs:
"ls\n"                    // Run "ls" command
"\x1b[A"                  // Arrow up
"\x1b[3~"                 // Delete key
"echo hello\n"            // Run "echo hello"
```

### Connection Lifecycle

**1. QUIC Handshake** (1-2 RTT):
```
Client                                    Server
  │                                         │
  │─── Client Hello (TLS 1.3) ────────────>│
  │                                         │
  │<── Server Hello + Certificate ─────────│
  │                                         │
  │─── Client Finished (Verify cert) ─────>│
  │                                         │
  │<─── Server Finished ───────────────────│
  │                                         │
  │        QUIC Connection Established     │
```

**2. Auth Token Exchange** (Application layer):
```
Client                                    Server
  │                                         │
  │─── AuthToken (256-bit) ────────────────>│
  │                                         │
  │<───── Auth (if valid) OR Error ─────────│
  │                                         │
  │        Authenticated Session            │
```

**3. Data Transfer** (Bidirectional streams):
```
Client                                    Server
  │                                         │
  │<──── TerminalEvent::Output ─────────────│
  │                                         │
  │─── UserInput ("ls\n") ─────────────────>│
  │                                         │
  │<──── TerminalEvent::Output ─────────────│
  │                                         │
  │─── UserInput ("\x1b[A") ───────────────>│
  │                                         │
```

**4. Connection Close**:
```
Client                                    Server
  │                                         │
  │─── QUIC CLOSE (app code 0) ────────────>│
  │                                         │
  │<───── QUIC CLOSE (ack) ─────────────────│
  │                                         │
  │        Connection Closed                │
```

### Stream Management

**Stream Types** (QUIC):
- **Unidirectional**: Client → Server (user input)
- **Unidirectional**: Server → Client (terminal output)
- **Bidirectional**: Future use (file transfer, etc.)

**Current Implementation**: Unidirectional streams (simpler, sufficient for terminal)

---

## Security Architecture

### Threat Model

**Assets to Protect**:
1. Terminal access (command execution)
2. Terminal output (sensitive data)
3. AuthToken (session authentication)
4. Certificate fingerprint (identity verification)

**Attackers**:
1. **Network Attacker**: Can intercept/modify packets
2. **Malicious Host**: Impersonates legitimate host
3. **Compromised Device**: Mobile device or host agent stolen/hacked

### Defense in Depth

**Layer 1: Transport Security** (TLS 1.3)
- Encryption: AES-256-GCM
- Authentication: Certificate-based
- Forward secrecy: Ephemeral key exchange

**Layer 2: Certificate Verification** (TOFU)
- Fingerprint: SHA256 hash of certificate
- Comparison: Case-insensitive, separator-agnostic
- Storage: Secure storage (Keychain/Keystore)

**Layer 3: Application Authentication** (AuthToken)
- Token: 256-bit cryptographically secure random
- Scope: Valid until host agent restarts
- Validation: Checked on every connection

**Layer 4: Secure Storage**
- iOS: Keychain Services (kSecClassGenericPassword)
- Android: Keystore System (AndroidKeyStore)
- Encryption: AES-256 with hardware-backed keystore

### TOFU Security Model

**Trust-On-First-Use Workflow**:
```
┌─────────────────────────────────────────────────────────────┐
│ Initial Pairing (One-time, Secure Channel)                  │
├─────────────────────────────────────────────────────────────┤
│ 1. Host Agent generates certificate + AuthToken             │
│ 2. Host Agent displays QR code (local network)              │
│ 3. Mobile app scans QR code (physical proximity)            │
│ 4. Mobile app connects, verifies fingerprint                │
│ 5. Mobile app saves credentials (TOFU - auto-trust)          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Subsequent Connections (Zero-Trust Verification)            │
├─────────────────────────────────────────────────────────────┤
│ 1. Mobile app loads saved fingerprint                       │
│ 2. Mobile app connects to host                              │
│ 3. Host presents certificate                                │
│ 4. Mobile app calculates SHA256 fingerprint                │
│ 5. Mobile app compares with saved fingerprint               │
│    - If match → Connection allowed                          │
│    - If mismatch → Connection rejected (MitM detected)      │
│ 6. Mobile app sends AuthToken                               │
│ 7. Host validates token                                     │
│ 8. Session established                                      │
└─────────────────────────────────────────────────────────────┘
```

**Risks & Mitigations**:

| Threat | Risk Level | Mitigation |
|--------|------------|------------|
| First-connection MitM | Medium | Local network pairing, physical access |
| Fingerprint collision | Negligible | SHA256 (256-bit space) |
| Token leakage | Low | Secure storage, never logged, ephemeral |
| Certificate expiration | Low | User warning, manual re-pairing |
| Device theft | Medium | Secure storage (locked with device auth) |

### Cryptographic Choices

**Certificate Algorithm**: ECDSA (P-256)
- Smaller certificates than RSA
- Faster verification
- Widely supported

**Hash Algorithm**: SHA256
- Collision-resistant
- Widely supported
- Fast computation

**Token Generation**: ChaCha20 RNG (ring crate)
- Cryptographically secure
- Thread-safe
- Hardware acceleration (if available)

**Key Exchange**: X25519 (TLS 1.3)
- Fast key exchange
- Forward secrecy
- Small keys (32 bytes)

---

## Deployment Architecture

### Development Environment

**Host Agent** (Development):
```bash
cargo run -p host_agent -- --port 8443 --verbose
```

**Mobile Bridge** (Development):
```bash
# Build Rust FFI
cargo build -p mobile_bridge

# Generate FRB bindings
flutter_rust_bridge_codegen \
  --rust-input crates/mobile_bridge/src/api.rs \
  --dart-output mobile/lib/bridge/bridge_generated.dart
```

**Mobile App** (Development):
```bash
# iOS
cd mobile && flutter run -d ios

# Android
cd mobile && flutter run -d android
```

### Production Deployment

**Host Agent** (Desktop):
- **macOS**: `.app` bundle (signed, notarized)
- **Linux**: Binary executable (statically linked)
- **Windows**: `.exe` installer (signed)

**Mobile App** (App Stores):
- **iOS**: App Store (TestFlight → Production)
- **Android**: Play Store (Internal → Production)

### CI/CD Pipeline

**Rust Workspace**:
```yaml
# .github/workflows/rust.yml
name: Rust CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
      - run: cargo test --workspace
      - run: cargo clippy --workspace -- -D warnings
      - run: cargo fmt --all -- --check
```

**Flutter App**:
```yaml
# .github/workflows/flutter.yml
name: Flutter CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter test
      - run: flutter analyze
```

---

## Technology Decisions

### Why QUIC?

**Pros**:
- **Faster connection**: 1-2 RTT vs 3 RTT for TCP+TLS
- **Better mobility**: Handles network changes gracefully
- **Multiplexing**: Multiple streams over single connection
- **Built-in security**: TLS 1.3 mandatory

**Cons**:
- **Complexity**: More complex than TCP
- **Debugging**: Harder to debug (encrypted, UDP-based)
- **Firewalls**: Some firewalls block UDP

**Decision**: QUIC is optimal for mobile terminal access (low latency, high reliability)

### Why Rustls?

**Pros**:
- **Memory-safe**: No buffer overflows
- **Modern**: Async-first, TLS 1.3 support
- **No external deps**: Pure Rust, no OpenSSL
- **Performant**: Comparable to OpenSSL in benchmarks

**Cons**:
- **Less mature**: Younger than OpenSSL
- **Limited audit**: Fewer security audits

**Decision**: Rustls aligns with project goals (safety, performance, modern)

### Why Flutter?

**Pros**:
- **Single codebase**: iOS + Android from one codebase
- **Native performance**: 60fps UI, native ARM code
- **Rich ecosystem**: xterm_flutter, mobile_scanner, etc.
- **Fast development**: Hot reload, excellent tooling

**Cons**:
- **Binary size**: Larger than native apps
- **Learning curve**: Dart language, widget system

**Decision**: Flutter enables rapid cross-platform development with native quality

### Why Postcard?

**Pros**:
- **Zero-copy**: Deserializes from bytes without allocation
- **Small**: Compact binary format (smaller than JSON)
- **No-Schema**: Deserialize into Rust structs directly
- **Fast**: Benchmarks show 2-3x faster than serde_json

**Cons**:
- **Rust-only**: Not interoperable with other languages
- **No-self-describing**: Requires known types

**Decision**: Postcard is optimal for Rust ↔ Dart FFI (via FRB)

---

## Performance Characteristics

### Latency

**Connection Establishment**:
- QUIC handshake: ~10-50ms (local network)
- Certificate verification: ~1ms
- Token validation: <1ms
- **Total**: ~20-100ms (local network)

**Data Transfer**:
- Terminal output: <10ms (local network)
- User input: <10ms (local network)
- **Round-trip**: ~20ms (local network)

### Throughput

**Terminal Output**:
- Typical: 1-10 KB/s (interactive shell)
- Max: 1+ MB/s (cat large file)
- Streaming: Continuous (no buffering)

### Memory Usage

**Host Agent**:
- Base: ~10 MB
- Per connection: ~1-2 MB
- PTY buffer: ~100 KB

**Mobile App**:
- Base: ~30 MB (Flutter runtime)
- Per connection: ~5 MB
- Terminal buffer: ~10 MB (10k lines)

### Battery Impact

**Mobile App** (Active session):
- CPU: ~5-10% (background streaming)
- Network: ~1-2% (QUIC keep-alive)
- **Total**: ~5-10%/hour (typical usage)

---

## Future Enhancements

### Short-term (Phase 05-06)
1. **Stream I/O**: Complete receive_event/send_command implementation
2. **mDNS Discovery**: Automatic host discovery on local network
3. **Multiple Hosts**: Support for saved hosts
4. **Connection History**: Track recent connections

### Medium-term (Post-MVP)
1. **File Transfer**: Upload/download files over QUIC
2. **Port Forwarding**: SSH-like port forwarding
3. **Terminal Tabs**: Multiple terminals in one session
4. **Session Recording**: Record/replay terminal sessions

### Long-term
1. **End-to-End Encryption**: E2E encryption for terminal output
2. **Multi-User**: Support for multiple simultaneous users
3. **Cloud Relay**: Relay through cloud for remote access
4. **Web Client**: Browser-based terminal (WebAssembly)

---

**Last Updated**: 2026-01-07
**Maintainer**: Comacode Development Team
**Next Review**: Phase 05 completion
