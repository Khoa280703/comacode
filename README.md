# Comacode

Remote terminal access via QR code pairing + QUIC.

## Quick Start

```bash
# Build
cargo build --release

# Run hostagent (server)
./target/release/hostagent --host 0.0.0.0 --port 8443

# Run CLI client (for testing)
./target/release/cli_client --host 127.0.0.1 --port 8443
```

## Features

- **QR Code Pairing**: Scan QR to get connection params (IP, port, token, fingerprint)
- **QUIC Protocol**: Fast, secure UDP-based transport with Quinn 0.11
- **TOFU Verification**: Trust On First Use for certificate fingerprint
- **Rate Limiting**: IP-based ban system (in-memory)
- **Mobile Bridge**: FFI layer for Flutter app integration

## Architecture

```
┌─────────────┐     QUIC      ┌─────────────┐
│  Mobile App │ ◄────────────► │  Hostagent  │
│  (Flutter)  │               │  (Rust)     │
└─────────────┘               └─────────────┘
                                      │
                                      ▼
                                ┌───────────┐
                                │   PTY     │
                                └───────────┘
```

## Crates

| Crate | Purpose |
|-------|---------|
| `core` | Shared types (AuthToken, TerminalEvent, NetworkMessage) |
| `hostagent` | Server binary with PTY + QUIC server |
| `mobile_bridge` | FFI bridge for Flutter (QUIC client) |
| `cli_client` | CLI client for testing |

## Development

**Requirements**: Rust 1.75+, Flutter 3.15+ (for mobile)

```bash
# Run tests
cargo test

# Run with logs
RUST_LOG=debug ./target/release/hostagent

# Generate FFI code
cd mobile && flutter pub run build_runner build
```

## Status

**Phase**: 04.1 (Post-MVP Bugfix)

- ✅ Phase 01-03: MVP (hostagent, auth, rate limiting, PTY, QUIC server)
- ✅ Phase 04: QUIC Client for Mobile
- ✅ Phase 04.1: Critical Bugfixes (UB fix, fingerprint leakage)
- ⏳ Phase 05: Network Protocol (Stream I/O)

## Known Issues

See `plans/260106-2127-comacode-mvp/known-issues-technical-debt.md`

## License

MIT
