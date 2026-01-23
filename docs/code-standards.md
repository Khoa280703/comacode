# Comacode Code Standards & Architecture

> Version: 1.3 | Last Updated: 2026-01-22
> Phase: Phase VFS-2 - Virtual File System (File Watcher) - Flutter UI Complete

---

## Table of Contents
- [Codebase Structure](#codebase-structure)
- [Rust Coding Standards](#rust-coding-standards)
- [Flutter Coding Standards](#flutter-coding-standards)
- [Testing Standards](#testing-standards)
- [Error Handling Patterns](#error-handling-patterns)
- [Security Guidelines](#security-guidelines)
- [Performance Guidelines](#performance-guidelines)
- [Documentation Standards](#documentation-standards)

---

## Codebase Structure

### Workspace Organization

```
Comacode/
├── crates/                    # Rust workspace
│   ├── core/                  # Shared business logic
│   │   ├── src/
│   │   │   ├── types/         # Data types (TerminalEvent, AuthToken, QrPayload, DirEntry)
│   │   │   ├── auth.rs        # Authentication logic
│   │   │   ├── error.rs       # Error types (including VFS errors)
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   ├── hostagent/             # Host agent binary
│   │   ├── src/
│   │   │   ├── vfs.rs         # VFS operations (NEW Phase VFS-1)
│   │   │   ├── quic_server.rs # QUIC server
│   │   │   ├── pty.rs         # PTY manager
│   │   │   └── main.rs
│   │   └── Cargo.toml
│   │
│   └── mobile_bridge/         # FFI bridge for Flutter
│       ├── src/
│       │   ├── lib.rs         # Module exports
│       │   ├── api.rs         # FFI bridge functions (VFS API added)
│       │   └── quic_client.rs # QUIC client implementation
│       └── Cargo.toml
│
├── mobile/                    # Flutter app (Phase 04)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── core/              # Core utilities
│   │   │   ├── theme.dart
│   │   │   └── storage.dart
│   │   ├── features/          # Feature modules
│   │   │   ├── terminal/      # Terminal UI with xterm_flutter
│   │   │   ├── connection/    # Connection state management (Riverpod)
│   │   │   ├── vfs/           # VFS browser UI
│   │   │   └── qr_scanner/    # QR scanner with mobile_scanner
│   │   └── bridge/            # FFI bindings
│   │       ├── bridge_generated.dart
│   │       └── bridge.dart
│   ├── ios/
│   └── android/
│
├── docs/                      # Documentation
│   ├── codebase-summary.md
│   ├── project-overview-pdr.md
│   ├── code-standards.md      # This file
│   ├── design-guidelines.md
│   └── system-architecture.md
│
└── plans/                     # Development plans
    ├── 260106-2127-comacode-mvp/
    └── reports/
```

### Module Organization Principles

**Rust**:
- **One concern per module**: Network, FFI, crypto, etc. separated
- **Private implementation details**: Hide structs, expose traits
- **Feature-based organization**: Group by functionality, not layer

**Flutter**:
- **Feature-first structure**: Organize by user-facing features
- **Shared utilities in core/**: Reusable components
- **Bridge isolation**: FFI code in separate directory

---

## Rust Coding Standards

### Naming Conventions

**Structs and Enums**: `PascalCase`
```rust
pub struct QuicClient { }
pub enum TerminalEvent { }
pub struct TofuVerifier { }
```

**Functions and Methods**: `snake_case`
```rust
pub fn connect_to_host() { }
pub async fn receive_event() { }
pub fn normalize_fingerprint() { }
```

**Constants**: `SCREAMING_SNAKE_CASE`
```rust
const DEFAULT_IDLE_TIMEOUT_SECS: u64 = 10;
const MAX_CONNECTION_ATTEMPTS: u32 = 3;
```

**Type Parameters**: `T` (single uppercase letter)
```rust
pub fn parse_option<T>(value: Option<T>) -> T { }
```

### Code Organization

**File Structure**:
```rust
// 1. Module documentation
//! QUIC client for Flutter bridge
//!
//! Phase 04: Mobile App - QUIC client with TOFU verification

// 2. Imports (grouped and sorted)
use comacode_core::{TerminalEvent, AuthToken};
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, error, debug};

use quinn::{ClientConfig, Endpoint, Connection};
use rustls::client::danger::{ServerCertVerified, ServerCertVerifier};

// 3. Type aliases (if any)
type Fingerprint = String;

// 4. Structs
pub struct QuicClient { }

struct TofuVerifier { }

// 5. Trait implementations
impl ServerCertVerifier for TofuVerifier { }

impl QuicClient {
    // Associated functions (methods)
    pub fn new() -> Self { }
    pub async fn connect(&mut self) -> Result<(), String> { }
}

// 6. Standalone functions
pub fn normalize_fingerprint(fp: &str) -> String { }

// 7. Tests module
#[cfg(test)]
mod tests { }
```

### Error Handling

**Use `Result<T, String>` for FFI-boundary code**:
```rust
pub async fn connect(&mut self, host: String) -> Result<(), String> {
    if host.is_empty() {
        return Err("Host cannot be empty".to_string());
    }

    let addr = format!("{}:{}", host, port)
        .parse::<std::net::SocketAddr>()
        .map_err(|e| format!("Invalid address: {}", e))?;

    Ok(())
}
```

**Use `thiserror` for internal errors** (future):
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum QuicClientError {
    #[error("Host cannot be empty")]
    EmptyHost,

    #[error("Invalid address: {0}")]
    InvalidAddress(#[from] std::net::AddrParseError),

    #[error("Connection failed: {0}")]
    ConnectionFailed(String),
}
```

**Error Message Guidelines**:
- **Be specific**: "Invalid address" > "Error"
- **Include context**: "Connection failed to 192.168.1.1:8443" > "Connection failed"
- **User-friendly**: Avoid technical jargon for FFI errors

### Async Patterns

**Use `async fn` for I/O operations**:
```rust
pub async fn connect(&mut self, host: String) -> Result<(), String> {
    let connection = self.endpoint.connect(...).await?;
    Ok(())
}
```

**Use `.await` directly, no blocking**:
```rust
// ❌ BAD: Blocks thread
let result = some_async_function().await.unwrap();

// ✅ GOOD: Propagate errors
let result = some_async_function().await?;
```

**Spawn tasks for background work** (future):
```rust
pub async fn connect_with_streaming(
    &mut self,
    sink: StreamSink<TerminalEvent>,
) -> Result<(), String> {
    let connection = self.connection.clone().unwrap();

    tokio::spawn(async move {
        loop {
            let event = connection.receive_event().await.unwrap();
            sink.add(event);
        }
    });

    Ok(())
}
```

### Unsafe Code

**Avoid `unsafe` unless absolutely necessary**:
```rust
// ❌ BAD: Unsafe static mutable (UB risk) - FIXED in Phase 04.1
// static mut QUIC_CLIENT: Option<QuicClient> = None;

// ✅ GOOD: Use once_cell (implemented in Phase 04.1)
use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::sync::Mutex;

static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();

// Thread-safe initialization
fn init_client() -> Result<(), String> {
    let client = QuicClient::new();
    QUIC_CLIENT.set(Arc::new(Mutex::new(client)))
        .map_err(|_| "Already initialized".to_string())
}

// Safe access
async fn get_client() -> &'static Arc<Mutex<QuicClient>> {
    QUIC_CLIENT.get().expect("Client not initialized")
}
```

**Benefits of OnceCell pattern**:
- Thread-safe initialization (atomic operations)
- One-time initialization guarantee
- Zero unsafe blocks required
- Works with async runtimes (Tokio)

**Document all `unsafe` blocks**:
```rust
/// # Safety
///
/// This function is safe because:
/// 1. The pointer is guaranteed to be non-null
/// 2. The memory is valid for the lifetime 'a
/// 3. No mutable references exist simultaneously
unsafe fn safe_function() { }
```

### Trait Implementation

**Implement traits completely** (all required methods):
```rust
impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        // Implementation
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}
```

### Documentation

**Module-level documentation**:
```rust
//! QUIC client for Flutter bridge
//!
//! Phase 04: Mobile App - QUIC client with TOFU verification
//!
//! ## Implementation Notes
//!
//! Uses Quinn 0.11 + Rustls 0.23 with custom TOFU certificate verifier.
//! The fingerprint is normalized (case-insensitive, separator-agnostic)
//! before comparison.
//!
//! ## Example
//!
//! ```no_run
//! use comacode_mobile_bridge::QuicClient;
//!
//! #[tokio::main]
//! async fn main() {
//!     let mut client = QuicClient::new("AA:BB:CC".to_string());
//!     client.connect("192.168.1.1".to_string(), 8443).await.unwrap();
//! }
//! ```
```

**Function documentation**:
```rust
/// Connect to remote host using QUIC with TOFU verification
///
/// # Arguments
///
/// * `host` - Server IP address or hostname
/// * `port` - QUIC server port
/// * `auth_token` - Authentication token (validated but not used in this phase)
///
/// # Returns
///
/// Returns `Ok(())` if connection successful, `Err(String)` otherwise.
///
/// # Errors
///
/// Returns error if:
/// - Host is empty
/// - Port is 0
/// - Auth token is invalid
/// - Connection fails
///
/// # Example
///
/// ```no_run
/// # use comacode_mobile_bridge::QuicClient;
/// # #[tokio::main]
/// # async fn main() {
/// let mut client = QuicClient::new("AA:BB:CC".to_string());
/// client.connect("192.168.1.1".to_string(), 8443, "token".to_string()).await.unwrap();
/// # }
/// ```
pub async fn connect(&mut self, host: String, port: u16, auth_token: String) -> Result<(), String> {
    // Implementation
}
```

---

## Flutter Coding Standards

### Naming Conventions

**Classes and Enums**: `PascalCase`
```dart
class QuicClient { }
enum ConnectionState { }
class TofuVerifier { }
```

**Variables and Functions**: `camelCase`
```dart
String serverFingerprint = '';
void connectToHost() { }
bool isConnected = false;
```

**Constants**: `lowerCamelCase` (with `final` or `const`)
```dart
final String serverFingerprint = 'AA:BB:CC';
const int defaultTimeoutSecs = 10;
```

**Private Members**: Prefix with `_`
```dart
class ConnectionProvider {
  String? _currentHost;
  bool _isConnected = false;
}
```

### Code Organization

**File Structure**:
```dart
// 1. Documentation
/// Connection state manager for QUIC client
///
/// Manages connection lifecycle, credential storage, and state updates.

// 2. Imports (grouped and sorted)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/bridge.dart';
import '../core/storage.dart';

// 3. Type definitions (if any)
typedef ConnectionStateCallback = void Function(bool isConnected);

// 4. Classes
class ConnectionProvider extends ChangeNotifier {
  // Fields
  bool _isConnected = false;

  // Getters
  bool get isConnected => _isConnected;

  // Constructors
  ConnectionProvider();

  // Public methods
  Future<void> connect(String host, int port) async { }

  // Private methods
  void _updateState() { }
}
```

### State Management

**Use Provider pattern**:
```dart
class ConnectionProvider extends ChangeNotifier {
  bool _isConnected = false;
  String? _error;

  bool get isConnected => _isConnected;
  String? get error => _error;

  Future<void> connect(QrPayload payload) async {
    try {
      _setLoading(true);
      _error = null;

      await _doConnect(payload);

      _isConnected = true;
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  void _setLoading(bool loading) {
    // Update loading state
    notifyListeners();
  }
}

// Usage in Widget
class TerminalPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        if (connection.isConnected) {
          return TerminalWidget();
        } else {
          return ConnectingWidget();
        }
      },
    );
  }
}
```

### Async Patterns

**Use `async`/`await` for async operations**:
```dart
Future<void> connect(String host, int port) async {
  try {
    await ComacodeBridge.connect(
      host: host,
      port: port,
      token: token,
      fingerprint: fingerprint,
    );
  } catch (e) {
    throw Exception('Connection failed: $e');
  }
}
```

**Use `FutureBuilder` for async UI**:
```dart
FutureBuilder<String>(
  future: _getLastHost(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return CircularProgressIndicator();
    } else if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    } else {
      return Text('Last host: ${snapshot.data}');
    }
  },
)
```

### Error Handling

**Use `try`/`catch` with specific exceptions**:
```dart
try {
  await connection.connect(payload);
} on SocketException catch (e) {
  showError('Network error: ${e.message}');
} on TofuVerificationException catch (e) {
  showError('Certificate mismatch: ${e.message}');
} catch (e) {
  showError('Unknown error: $e');
}
```

**Return `Result<T, E>`-like pattern** (or custom):
```dart
class ConnectionResult {
  final bool success;
  final String? error;

  ConnectionResult.success()
      : success = true,
        error = null;

  ConnectionResult.failure(this.error)
      : success = false;
}

Future<ConnectionResult> connect(...) async {
  try {
    await _doConnect();
    return ConnectionResult.success();
  } catch (e) {
    return ConnectionResult.failure(e.toString());
  }
}
```

### Widget Organization

**Split widgets into small, reusable components**:
```dart
// terminal_page.dart
class TerminalPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: TerminalWidget(),
      bottomNavigationBar: VirtualKeyBar(),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text('Terminal'),
      actions: [
        IconButton(icon: Icon(Icons.settings), onPressed: () => _openSettings(context)),
      ],
    );
  }
}

// virtual_key_bar.dart
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
        ],
      ),
    );
  }

  Widget _buildKey(String label, {VoidCallback? onPressed}) {
    return ElevatedButton(
      child: Text(label),
      onPressed: onPressed,
    );
  }
}
```

### Theme and Styling

**Use Catppuccin Mocha theme**:
```dart
class CatppuccinMocha {
  static const base = Color(0xFF1E1E2E);
  static const surface = Color(0xFF313244);
  static const primary = Color(0xFFCBA6F7);
  static const text = Color(0xFFCDD6F4);
  static const green = Color(0xFFA6E3A1);
  static const red = Color(0xFFF38BA8);
  static const yellow = Color(0xFFF9E2AF);
  static const blue = Color(0xFF89B4FA);
  static const mauve = Color(0xFFCBA6F7);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: CatppuccinMocha.primary,
      surface: CatppuccinMocha.surface,
      onPrimary: CatppuccinMocha.base,
      onSurface: CatppuccinMocha.text,
    ),
    scaffoldBackgroundColor: CatppuccinMocha.base,
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: CatppuccinMocha.text, fontSize: 14),
      bodyMedium: TextStyle(color: CatppuccinMocha.text, fontSize: 13),
    ),
  );
}
```

**Use consistent spacing**:
```dart
class Spacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

Padding(
  padding: EdgeInsets.all(Spacing.md),
  child: Text('Hello'),
)
```

---

## Testing Standards

### Flutter Self-Testing Policy

**IMPORTANT:** The developer handles all Flutter testing manually. The AI assistant should **NOT** run Flutter testing commands.

#### Commands to AVOID

Do NOT run these commands:
- `flutter run`
- `flutter test`
- `flutter build ios`
- `flutter build apk`
- `flutter devices`

#### Developer Responsibilities

The developer will:
1. Run Flutter app on physical iOS device manually
2. Test QR scanning and connection flow
3. Test terminal command sending and output display
4. Test virtual keyboard functionality
5. Report any issues with logs

#### Assistant Responsibilities

The assistant should:
1. Build Rust code: `cargo build --release --manifest-path=crates/Cargo.toml`
2. Generate FRB bindings when needed
3. Fix code issues based on developer-reported bugs
4. Provide code changes only - no Flutter execution

#### Why This Policy?

1. **iOS device requirement** - App needs physical device for proper testing (camera, network)
2. **Developer environment** - Only developer has access to iOS simulator and devices
3. **Faster iteration** - Developer can immediately test changes on their device
4. **Avoid Xcode issues** - AI cannot interact with Xcode simulator/device picker

### Rust Testing

**Unit tests**: Test individual functions and methods
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_fingerprint() {
        assert_eq!(TofuVerifier::normalize_fingerprint("AA:BB:CC"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("aa:bb:cc"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("aabbcc"), "AABBCC");
    }

    #[test]
    fn test_fingerprint_calculation() {
        let verifier = TofuVerifier::new("AA:BB:CC".to_string());
        let cert = CertificateDer::from(vec![0x42u8]);
        let fingerprint = verifier.calculate_fingerprint(&cert);
        assert!(fingerprint.len() == 95);
    }

    #[tokio::test]
    async fn test_quic_client_invalid_host() {
        let mut client = QuicClient::new("AA:BB:CC".to_string());
        let result = client.connect("".to_string(), 8443, "token".to_string()).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Host cannot be empty"));
    }
}
```

**Integration tests**: Test multiple components together
```rust
// tests/integration_test.rs
use comacode_mobile_bridge::QuicClient;

#[tokio::test]
async fn test_full_connection_flow() {
    // 1. Create client
    let mut client = QuicClient::new("AA:BB:CC".to_string());

    // 2. Connect to test server
    client.connect("127.0.0.1".to_string(), 8443, "token".to_string()).await.unwrap();

    // 3. Verify connection
    assert!(client.is_connected().await);

    // 4. Disconnect
    client.disconnect().await.unwrap();
    assert!(!client.is_connected().await);
}
```

### Flutter Testing

**Widget tests**: Test UI components
```dart
testWidgets('VirtualKeyBar renders keys', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VirtualKeyBar(
        onKeyPressed: (key) {},
      ),
    ),
  );

  expect(find.text('ESC'), findsOneWidget);
  expect(find.text('CTRL'), findsOneWidget);
});

testWidgets('VirtualKeyBar calls callback on press', (tester) async {
  String? pressedKey;

  await tester.pumpWidget(
    MaterialApp(
      home: VirtualKeyBar(
        onKeyPressed: (key) => pressedKey = key,
      ),
    ),
  );

  await tester.tap(find.text('ESC'));
  expect(pressedKey, '\x1b');
});
```

**Unit tests**: Test business logic
```dart
test('QrPayload parses valid JSON', () {
  final json = '{"ip":"192.168.1.1","port":8443,"fingerprint":"AA:BB","token":"DEAD","protocol_version":1}';

  final payload = QrPayload.fromJson(jsonDecode(json));

  expect(payload.ip, '192.168.1.1');
  expect(payload.port, 8443);
  expect(payload.fingerprint, 'AA:BB');
});

test('QrPayload throws on invalid JSON', () {
  final json = '{"invalid":"data"}';

  expect(() => QrPayload.fromJson(jsonDecode(json)), throwsFormatException);
});
```

---

## Error Handling Patterns

### Rust Error Handling

**Prefer `Result<T, E>` over `Option<T>`** for errors:
```rust
// ❌ BAD: Loses error context
pub fn connect(&mut self) -> Option<Connection> {
    // ...
}

// ✅ GOOD: Provides error context
pub fn connect(&mut self) -> Result<Connection, String> {
    // ...
}
```

**Use `.map_err()` to add context**:
```rust
let addr = format!("{}:{}", host, port)
    .parse::<std::net::SocketAddr>()
    .map_err(|e| format!("Invalid address {}:{}: {}", host, port, e))?;
```

**Use `?` operator for error propagation**:
```rust
pub async fn connect(&mut self) -> Result<(), String> {
    let verifier = Arc::new(TofuVerifier::new(self.fingerprint.clone()));
    let rustls_config = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(rustls_config)
        .map_err(|e| format!("Failed to create QUIC crypto: {}", e))?;
    Ok(())
}
```

### Flutter Error Handling

**Use exceptions with specific types**:
```dart
class ConnectionException implements Exception {
  final String message;
  ConnectionException(this.message);

  @override
  String toString() => 'ConnectionException: $message';
}

try {
  await client.connect();
} on ConnectionException catch (e) {
  showError('Connection failed: ${e.message}');
}
```

**Use `Result`-like pattern for better error handling**:
```dart
class Result<T> {
  final T? data;
  final String? error;

  Result.success(this.data)
      : error = null;

  Result.failure(this.error)
      : data = null;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  void onSuccess(void Function(T data) callback) {
    if (isSuccess && data != null) {
      callback(data!);
    }
  }

  void onFailure(void Function(String error) callback) {
    if (isFailure && error != null) {
      callback(error!);
    }
  }
}
```

---

## Security Guidelines

### Rust Security

**No secrets in code**:
```rust
// ❌ BAD: Hardcoded secret
const API_KEY: &str = "sk_live_1234567890";

// ✅ GOOD: Load from environment
const API_KEY: &str = env!("API_KEY");
```

**Validate all inputs**:
```rust
pub async fn connect(&mut self, host: String, port: u16, token: String) -> Result<(), String> {
    if host.is_empty() {
        return Err("Host cannot be empty".to_string());
    }
    if port == 0 {
        return Err("Port cannot be 0".to_string());
    }

    let _token = AuthToken::from_hex(&token)
        .map_err(|e| format!("Invalid auth token: {}", e))?;

    // Continue...
}
```

**Use constant-time comparison for secrets**:
```rust
// ❌ BAD: Timing-vulnerable
if actual_fingerprint == expected_fingerprint { }

// ✅ GOOD: Constant-time (use subtle crate)
use subtle::ConstantTimeEq;

if actual_fingerprint.as_bytes().ct_eq(expected_fingerprint.as_bytes()).into() { }
```

**Don't log sensitive data**:
```rust
// ❌ BAD: Logs actual fingerprint
debug!("Expected: {}, Actual: {}", expected_fingerprint, actual_fingerprint);

// ✅ GOOD: Logs only first/last 4 chars
debug!("Expected: {}...{}, Actual: {}...{}",
    &expected_fingerprint[..4],
    &expected_fingerprint[expected_fingerprint.len()-4..],
    &actual_fingerprint[..4],
    &actual_fingerprint[actual_fingerprint.len()-4..]
);

// ✅ BETTER: Logs only result
debug!("Fingerprint match: {}", matches);
```

### Flutter Security

**Use secure storage for sensitive data**:
```dart
// ❌ BAD: Shared preferences (plaintext)
await prefs.setString('token', token);

// ✅ GOOD: Secure storage (encrypted)
await storage.write(key: 'token', value: token);
```

**Validate all inputs**:
```dart
QrPayload.fromJson(Map<String, dynamic> json) {
  if (json['ip'] == null || json['ip'].toString().isEmpty) {
    throw FormatException('IP cannot be empty');
  }
  if (json['port'] == null || json['port'] <= 0 || json['port'] > 65535) {
    throw FormatException('Port must be 1-65535');
  }
  // Continue...
}
```

**Don't log sensitive data**:
```dart
// ❌ BAD: Logs actual token
developer.log('Connecting with token: $token');

// ✅ GOOD: Logs redacted token
developer.log('Connecting with token: ${token.substring(0, 8)}...');
```

---

## Performance Guidelines

### Rust Performance

**Avoid allocations in hot paths**:
```rust
// ❌ BAD: Allocates Vec<String>
result.iter()
    .map(|b| format!("{:02X}", b))
    .collect::<Vec<String>>()
    .join(":")

// ✅ BETTER: Pre-allocate
let mut result = String::with_capacity(95);
for (i, b) in bytes.iter().enumerate() {
    if i > 0 {
        result.push(':');
    }
    result.push_str(&format!("{:02X}", b));
}
```

**Use async/await correctly**:
```rust
// ❌ BAD: Blocks thread
let result = some_blocking_function().await.unwrap();

// ✅ GOOD: Propagates errors
let result = some_blocking_function().await?;
```

**Reuse connections**:
```rust
// ✅ GOOD: Endpoint reused across connections
pub struct QuicClient {
    endpoint: Endpoint,  // Created once, reused
    connection: Option<Connection>,
}
```

### Flutter Performance

**Use `const` constructors**:
```dart
// ✅ GOOD: Const constructor
const SizedBox(height: 16);

// ❌ BAD: Non-const
SizedBox(height: 16);
```

**Avoid rebuilding widgets unnecessarily**:
```dart
// ❌ BAD: Rebuilds entire widget tree
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        return Column(
          children: [
            Text('Status: ${connection.isConnected}'),  // Changes frequently
            ExpensiveWidget(),  // Never changes but rebuilds every time
          ],
        );
      },
    );
  }
}

// ✅ GOOD: Uses child parameter
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        return Column(
          children: [
            Text('Status: ${connection.isConnected}'),
            child!,  // Doesn't rebuild
          ],
        );
      },
      child: ExpensiveWidget(),  // Built once
    );
  }
}
```

**Use `ListView.builder` for large lists**:
```dart
// ❌ BAD: Builds all items at once
ListView(
  children: items.map((item) => ItemWidget(item)).toList(),
)

// ✅ GOOD: Builds items lazily
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
)
```

---

## Documentation Standards

### Rust Documentation

**Required documentation**:
- Module-level: `//!` comments explaining purpose and context
- Public items: `///` comments with usage examples
- Unsafe blocks: `# Safety` section explaining invariants
- Errors: Document all possible error conditions

**Example format**:
```rust
/// Connect to remote host using QUIC with TOFU verification
///
/// # Arguments
///
/// * `host` - Server IP address or hostname
/// * `port` - QUIC server port
/// * `auth_token` - Authentication token
///
/// # Returns
///
/// Returns `Ok(())` if connection successful, `Err(String)` otherwise.
///
/// # Errors
///
/// Returns error if:
/// - Host is empty
/// - Port is 0
/// - Auth token is invalid
/// - Connection fails
///
/// # Example
///
/// ```no_run
/// use comacode_mobile_bridge::QuicClient;
///
/// #[tokio::main]
/// async fn main() {
///     let mut client = QuicClient::new("AA:BB:CC".to_string());
///     client.connect("192.168.1.1".to_string(), 8443, "token".to_string()).await.unwrap();
/// }
/// ```
pub async fn connect(&mut self, host: String, port: u16, auth_token: String) -> Result<(), String> {
    // Implementation
}
```

### Flutter Documentation

**Required documentation**:
- Classes: Purpose and usage
- Public methods: Parameters, return values, exceptions
- Complex logic: Inline comments explaining "why", not "what"

**Example format**:
```dart
/// Connection state manager for QUIC client
///
/// Manages connection lifecycle, credential storage, and state updates.
/// Uses [ChangeNotifier] to notify listeners of state changes.
///
/// Example:
/// ```dart
/// final connection = ConnectionProvider();
/// await connection.connect(payload);
/// print(connection.isConnected); // true
/// ```
class ConnectionProvider extends ChangeNotifier {
  /// Connect to host using scanned QR payload
  ///
  /// Validates fingerprint (TOFU), saves credentials on success,
  /// and notifies listeners of state changes.
  ///
  /// Throws [ConnectionException] if:
  /// - QR payload is invalid
  /// - Connection fails
  /// - Fingerprint mismatch
  Future<void> connect(QrPayload payload) async {
    // Implementation
  }
}
```

---

**Last Updated**: 2026-01-22
**Maintainer**: Comacode Development Team
**Next Review**: Phase VFS-3 completion

---

## Phase VFS-1 Updates

### VFS Module Organization

**New Module**: `crates/hostagent/src/vfs.rs`

**Structure**:
```rust
// VFS-specific result type
pub type VfsResult<T> = Result<T, VfsError>;

// VFS-specific errors
pub enum VfsError {
    IoError(String),
    PathNotFound(String),
    NotADirectory(String),
    PermissionDenied(String),
}

// Core functions
pub async fn read_directory(path: &Path) -> VfsResult<Vec<DirEntry>>;
pub fn chunk_entries(entries: Vec<DirEntry>, chunk_size: usize) -> Vec<Vec<DirEntry>>;
pub fn validate_path(path: &Path, allowed_base: &Path) -> VfsResult<()>;
```

**Error Conversion**:
```rust
impl From<VfsError> for CoreError {
    fn from(err: VfsError) -> Self {
        match err {
            VfsError::PathNotFound(p) => CoreError::PathNotFound(p),
            VfsError::NotADirectory(p) => CoreError::NotADirectory(p),
            VfsError::PermissionDenied(p) => CoreError::PermissionDenied(p),
            VfsError::IoError(e) => CoreError::VfsIoError(e),
        }
    }
}
```

### VFS FFI API Pattern

**Async Request/Response Pattern** (non-blocking):
```rust
// Request (sends to server)
pub async fn request_list_dir(path: String) -> Result<(), String>;

// Poll response (returns None if not ready)
pub async fn receive_dir_chunk() -> Result<Option<(u32, Vec<DirEntry>, bool)>, String>;

// Sync getters for DirEntry
#[frb(sync)]
pub fn get_dir_entry_name(entry: &DirEntry) -> String;

#[frb(sync)]
pub fn is_dir_entry_dir(entry: &DirEntry) -> bool;
```

### VFS Security Guidelines

**Path Validation**:
- Always use `canonicalize()` to resolve symlinks and relative paths
- Check if resolved path is within allowed base directory
- Return specific errors for different failure modes

**Example**:
```rust
pub fn validate_path(path: &Path, allowed_base: &Path) -> VfsResult<()> {
    let canonical = path.canonicalize()
        .map_err(|_| VfsError::PathNotFound(path.display().to_string()))?;

    let allowed_canonical = allowed_base.canonicalize()
        .unwrap_or_else(|_| allowed_base.to_path_buf());

    if !canonical.starts_with(&allowed_canonical) {
        return Err(VfsError::PermissionDenied(
            "Path traversal not allowed".to_string()
        ));
    }

    Ok(())
}
```

---

## Phase 04.1 Updates

### Global Static Pattern with OnceCell

Starting Phase 04.1, all global static state must use `once_cell::sync::OnceCell` instead of `static mut`:

**Pattern**:
```rust
use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::sync::Mutex;

static GLOBAL_STATE: OnceCell<Arc<Mutex<MyType>>> = OnceCell::new();

// Initialize once
fn init() {
    GLOBAL_STATE.set(Arc::new(Mutex::new(MyType::new())))
        .expect("Already initialized");
}

// Access safely
async fn access() {
    let state = GLOBAL_STATE.get()
        .expect("Not initialized");
    let mut guard = state.lock().await;
    // Use guard...
}
```

**Why this pattern?**
- Eliminates undefined behavior from `static mut`
- Thread-safe via atomic operations
- Compatible with async/await (no blocking)
- Zero unsafe blocks needed
