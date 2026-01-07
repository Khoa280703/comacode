# Comacode Codebase Summary

> Last Updated: 2026-01-07
> Version: Phase 04.1 (QUIC Client + Critical Bugfixes)

---

## Project Overview

Comacode is a remote terminal control system enabling mobile devices to connect to and control desktop terminals via QUIC protocol with TOFU (Trust On First Use) security model.

**Architecture**: Rust backend + Flutter mobile app
**Protocol**: QUIC (Quinn 0.11) over TLS 1.3
**Security**: TOFU certificate verification + AuthToken authentication

---

## Repository Structure

```
Comacode/
├── crates/
│   ├── core/                 # Shared types and business logic
│   │   └── src/
│   │       ├── types/        # TerminalEvent, AuthToken, QrPayload
│   │       ├── auth.rs       # AuthToken validation/generation
│   │       └── lib.rs
│   │
│   └── mobile_bridge/        # Rust FFI bridge for Flutter
│       ├── Cargo.toml        # Dependencies: quinn, rustls, flutter_rust_bridge
│       └── src/
│           ├── lib.rs        # Module exports
│           ├── api.rs        # FFI bridge functions (unsafe static - UB risk)
│           └── quic_client.rs # QUIC client with TOFU (Phase 04)
│
├── mobile/                   # Flutter app (TODO - Phase 04)
│   └── lib/
│
├── docs/                     # Documentation
│   ├── codebase-summary.md   # This file
│   ├── design-guidelines.md  # UI/UX specs (Catppuccin Mocha)
│   ├── tech-stack.md         # Technology choices
│   └── dogfooding-guide.md   # Internal testing guide
│
└── plans/                    # Development plans and reports
    ├── 260106-2127-comacode-mvp/
    │   ├── phase-01-project-setup.md
    │   ├── phase-02-rust-core.md
    │   ├── phase-03-host-agent.md
    │   ├── phase-04-mobile-app.md
    │   ├── phase-05-network-protocol.md
    │   └── phase-06-discovery-auth.md
    └── reports/
        └── code-reviewer-260107-1605-quic-client-phase04.md
```

---

## Phase 04 Implementation Status

### Phase 04 Completed Features ✅

1. **QUIC Client Implementation** (`crates/mobile_bridge/src/quic_client.rs`)
   - Full Quinn 0.11 + Rustls 0.23 integration
   - TOFU certificate verifier with fingerprint normalization
   - Connection management (connect, disconnect, is_connected)
   - AuthToken validation
   - 7 unit tests (all passing)
   - Zero clippy warnings

2. **Certificate Fingerprint Handling**
   - Case-insensitive comparison
   - Separator-agnostic (`:`, `-`, spaces)
   - SHA256 hash calculation
   - Human-readable format (`AA:BB:CC:...`)

3. **Dependencies Added**
   - `quinn = "0.11"` (QUIC protocol)
   - `rustls = { version = "0.23", features = ["ring"] }` (TLS)
   - `rustls-pki-types = "1.0"` (Rustls 0.23 compatibility)
   - `sha2 = "0.10"` (Fingerprint calculation)

### Phase 04.1 Critical Bugfixes ✅

4. **Fixed Undefined Behavior in FFI Bridge** (`api.rs`)
   - **Before**: `static mut QUIC_CLIENT: Option<QuicClient> = None` (UB risk)
   - **After**: `static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new()`
   - **Benefits**:
     - Thread-safe initialization via OnceCell
     - Zero unsafe blocks (previously had 3+ unsafe blocks)
     - Proper Arc<Mutex<T>> for concurrent access
     - No more compiler warnings

5. **Fixed Security: Fingerprint Leakage** (`quic_client.rs`)
   - **Before**: `debug!("Expected: {}, Actual: {}", expected, actual)` (leaks full fingerprint)
   - **After**: `debug!("Verifying cert - Match: {}", actual_clean == expected_clean)` (only result)
   - **Impact**: Sensitive data no longer logged in plaintext

### Partial Implementation ⚠️

6. **Stream I/O Methods** (Stub implementations - deferred to Phase 05)
   - `receive_event()`: Returns empty stub (TODO: Read from QUIC stream)
   - `send_command()`: Logs only (TODO: Write to QUIC stream)
   - **Blocks**: Flutter integration with StreamSink

---

## Key Components

### 1. Core Types (`crates/core/src/`)

**TerminalEvent**: Enum representing terminal output/events
```rust
pub enum TerminalEvent {
    Output(String),
    Error(String),
    Resize { width: u16, height: u16 },
    // ...
}
```

**AuthToken**: 256-bit authentication token
```rust
pub struct AuthToken([u8; 32]);

impl AuthToken {
    pub fn generate() -> Self;           // Secure random generation
    pub fn to_hex(&self) -> String;       // Hex encoding
    pub fn from_hex(hex: &str) -> Result<Self>; // Decoding
}
```

**QrPayload**: QR code pairing data
```rust
pub struct QrPayload {
    pub ip: String,
    pub port: u16,
    pub fingerprint: String,    // SHA256 cert fingerprint
    pub token: String,          // AuthToken hex
    pub protocol_version: u8,
}
```

### 2. QUIC Client (`crates/mobile_bridge/src/quic_client.rs`)

**TofuVerifier**: Custom certificate verifier for Trust-On-First-Use
```rust
struct TofuVerifier {
    expected_fingerprint: String,
}

impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(...) -> Result<ServerCertVerified, rustls::Error> {
        // SHA256 fingerprint calculation
        // Normalize and compare
        // Delegate signature verification to ring provider
    }
}
```

**QuicClient**: Main QUIC client for Flutter bridge
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
    pub async fn receive_event(&self) -> Result<TerminalEvent, String>; // STUB
    pub async fn send_command(&self, command: String) -> Result<(), String>; // STUB
    pub async fn disconnect(&mut self) -> Result<(), String>;
    pub async fn is_connected(&self) -> bool;
}
```

### 3. FFI Bridge (`crates/mobile_bridge/src/api.rs`)

**Purpose**: Expose Rust functions to Flutter via `flutter_rust_bridge`

**Current State**: Thread-safe implementation with once_cell (Phase 04.1)

**Key Implementation Details**:
- Uses `once_cell::sync::OnceCell` for global static
- Wrapped in `Arc<Mutex<T>>` for concurrent access
- Zero unsafe blocks (all UB risks eliminated)
- Functions: `connect_to_host`, `receive_terminal_event`, `send_terminal_command`, `disconnect`

**API Signature**:
```rust
pub async fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
) -> Result<(), String>;
```

---

## Technology Stack

### Backend (Rust)
- **QUIC**: Quinn 0.11 (async QUIC implementation)
- **TLS**: Rustls 0.23 with ring crypto provider
- **Serialization**: Serde + Postcard (binary format)
- **Async Runtime**: Tokio 1.x
- **FFI**: flutter_rust_bridge 1.80+
- **Crypto**: SHA2 (hashing), ring (signature verification)

### Mobile (Flutter) - TODO Phase 04
- **Terminal**: xterm_flutter (terminal emulation)
- **QR Scanner**: mobile_scanner 3.5+
- **Secure Storage**: flutter_secure_storage 9.0+
- **State Management**: Provider 6.0+
- **Permissions**: permission_handler 11.0+
- **Wakelock**: wakelock_plus 1.1+

---

## Security Model

### TOFU (Trust On First Use)
1. **First Connection**:
   - User scans QR code from Host Agent
   - QR contains: IP, port, fingerprint, auth token
   - Client connects and verifies fingerprint
   - If match → Save credentials (auto-trust)

2. **Subsequent Connections**:
   - Load saved credentials from secure storage
   - Verify fingerprint matches saved value
   - If mismatch → Connection rejected

### Risks & Mitigations
- **First Connection MitM**: Risk (by design for TOFU)
  - Mitigation: Use local network, physical access for initial pairing
- **Certificate Expiration**: Not handled (TODO)
- **Certificate Rotation**: Not handled (TODO)

### AuthToken
- 256-bit cryptographically secure random token
- Generated once at Host Agent startup
- Validates client authorization (separate from cert)

---

## Development Workflow

### Current Phase: Phase 04.1 - Mobile App (QUIC Client + Bugfixes)

**Status**: QUIC client complete with critical bugfixes, Flutter UI pending

**Phase 04 Completed**:
- ✅ QUIC client implementation (quic_client.rs)
- ✅ TOFU certificate verification
- ✅ Fingerprint normalization
- ✅ Unit tests (7 tests, all passing)
- ✅ Zero clippy warnings

**Phase 04.1 Completed**:
- ✅ Fixed UB in FFI bridge (api.rs)
- ✅ Replaced `static mut` with `once_cell::sync::OnceCell`
- ✅ Fixed fingerprint leakage in logs
- ✅ Thread-safe implementation

**Blocked**:
- ⏳ Stream I/O stub implementations (blocks Flutter integration)
- ⏳ Flutter project not created

**Next Steps**:
1. Implement stream I/O in Phase 05 (receive_event, send_command)
2. Generate FRB bindings for Flutter
3. Create Flutter project
4. Implement QR scanner
5. Implement terminal UI with xterm_flutter

### Testing Strategy

**Unit Tests** (Phase 04):
- ✅ Fingerprint calculation
- ✅ Fingerprint normalization (7 formats tested)
- ✅ Client creation
- ✅ Input validation (host, port, token)

**Integration Tests** (Blocked by Phase 03):
- ⏳ QUIC server not available
- ⏳ End-to-end connection flow
- ⏳ Stream I/O with real data

---

## Dependencies Summary

### Workspace Dependencies
```toml
[workspace.dependencies]
quinn = "0.11"
rustls = "0.23"
tokio = { version = "1.38", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
postcard = "1.0"
anyhow = "1.0"
tracing = "0.1"
sha2 = "0.10"
```

### Crate-Specific Dependencies

**mobile_bridge**:
```toml
quinn = { workspace = true }
rustls = { workspace = true, features = ["ring"] }
rustls-pki-types = "1.0"  # NEW in Phase 04
sha2 = { workspace = true }
flutter_rust_bridge = { workspace = true }
```

---

## Build Instructions

### Prerequisites
- Rust 1.70+ (2024 edition)
- Flutter 3.16+ (for Phase 04)
- iOS/Android SDK (for mobile deployment)

### Build Commands
```bash
# Build Rust workspace
cargo build --workspace

# Build mobile bridge FFI
cargo build -p mobile_bridge

# Generate FRB bindings (from mobile/ directory)
flutter_rust_bridge_codegen --rust-input ../crates/mobile_bridge/src/api.rs

# Run tests
cargo test --workspace

# Run clippy
cargo clippy --workspace -- -D warnings

# Run mobile bridge tests
cargo test -p mobile_bridge
```

---

## Known Technical Debt

### Critical (Must Fix)
1. ~~**Undefined Behavior in `api.rs`**~~ ✅ RESOLVED (Phase 04.1)
   - Was: `static mut QUIC_CLIENT` with unsafe access
   - Fixed: Replaced with `once_cell::sync::OnceCell<Arc<Mutex<QuicClient>>>`

2. **Stream I/O Stubs**
   - File: `crates/mobile_bridge/src/quic_client.rs:232-253`
   - Issue: receive_event/send_command return stubs
   - Fix: Implement actual QUIC stream reading/writing (deferred to Phase 05)

### High Priority (Should Fix)
3. ~~**Fingerprint Leakage in Logs**~~ ✅ RESOLVED (Phase 04.1)
   - Was: Actual fingerprint logged at line 88
   - Fixed: Now logs only match result

4. **Hardcoded Timeout**
   - File: `crates/mobile_bridge/src/quic_client.rs:206`
   - Issue: 10s timeout not configurable
   - Fix: Use const or make struct field

### Medium Priority (Nice to Have)
5. **Error Messages**
   - Generic errors in some places
   - Improve with more context

6. **Documentation**
   - Add security warnings
   - Add usage examples
   - Document panics

7. **Constant-Time Comparison**
   - Fingerprint comparison potentially timing-vulnerable
   - Use `subtle` crate

---

## Performance Considerations

### Connection Latency
- **QUIC Handshake**: ~1-2 RTT (vs TCP 1 RTT + TLS 2 RTT)
- **Certificate Verification**: O(n) where n = cert size
- **Fingerprint Calculation**: SHA256 hash (fast)

### Memory Usage
- **Per Connection**: ~10-20 KB (Quinn connection state)
- **Endpoint**: ~100 KB (socket buffers, config)
- **TofuVerifier**: ~1 KB (fingerprint string)

### Optimization Opportunities
1. Pre-allocate fingerprint string (currently allocates Vec<String>)
2. Reuse endpoint across connections (already implemented)
3. Connection pooling (if needed for multiple hosts)

---

## Compliance & Standards

### OWASP Top 10 (2021)
- ✅ A01 - Broken Access Control: Mitigated (AuthToken + fingerprint)
- ✅ A02 - Cryptographic Failures: Mitigated (SHA256, Rustls 0.23)
- ⚠️ A03 - Injection: Low risk (input validation present)
- ⚠️ A04 - Insecure Design: Acceptable for MVP (TOFU documented)
- ⚠️ A05 - Security Misconfiguration: Medium risk (fingerprint logs)
- ✅ A06 - Vulnerable Components: Pass (all up-to-date)
- ✅ A07 - Auth Failures: Mitigated (AuthToken + fingerprint)
- ✅ A09 - Logging Failures: Good (tracing throughout)

### Code Quality
- **Linting**: 0 clippy warnings for `quic_client.rs`
- **Testing**: 7 unit tests, all passing
- **Documentation**: Good (module docs, implementation notes)
- **Type Safety**: 100% (fully typed Rust)

---

## References

### Internal Documentation
- [Phase 04 Plan](../plans/260106-2127-comacode-mvp/phase-04-mobile-app.md)
- [Code Review Report](../plans/reports/code-reviewer-260107-1605-quic-client-phase04.md)
- [Design Guidelines](./design-guidelines.md)
- [Tech Stack](./tech-stack.md)

### External Resources
- [Quinn Documentation](https://docs.rs/quinn/0.11.0/quinn/)
- [Rustls 0.23 Migration Guide](https://github.com/rustls/rustls/releases/tag/v0.23.0)
- [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/)
- [TOFU Security Model](https://en.wikipedia.org/wiki/Trust_on_first_use)

---

## Maintenance Notes

### Version Policy
- Pin major versions (quinn 0.11, rustls 0.23)
- Update monthly, test thoroughly before upgrading
- Monitor security advisories via `cargo-audit`

### Testing Strategy
- Unit tests for all public methods
- Integration tests (blocked by Phase 03)
- Manual dogfooding (see [dogfooding-guide.md](./dogfooding-guide.md))

### Release Process
1. Update version in `Cargo.toml`
2. Update CHANGELOG.md
3. Tag release in git
4. Publish to crates.io (if applicable)
5. Generate FRB bindings
6. Update Flutter app

---

**Last Updated**: 2026-01-07
**Current Phase**: Phase 04.1 - QUIC Client Complete + Critical Bugfixes
**Next Milestone**: Phase 05 - Network Protocol (Stream I/O Implementation)
