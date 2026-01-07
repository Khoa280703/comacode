# Comacode

> Remote terminal access via QR code pairing

Scan QR code → Connect instantly → Control terminal from your phone

## Quick Start

```bash
# Install
cargo install --path .

# Start server
comacode-server --host 0.0.0.0 --port 8443

# Show QR code
comacode-server --qr
```

Then scan QR with mobile app (Flutter) to connect.

## What It Does

- **One-click pairing**: Scan QR, no manual IP/port entry
- **Secure**: Certificate fingerprint verification (TOFU)
- **Fast**: QUIC protocol (UDP-based, low latency)
- **Mobile-first**: Designed for phone-to-terminal access

## Use Cases

- **Server admin**: Access terminal from phone without laptop
- **IoT devices**: Control headless devices via mobile
- **Quick fixes**: Emergency access when SSH unavailable

## Requirements

- **Server**: Rust 1.75+, Linux/macOS
- **Client**: Flutter app (iOS/Android)

## Architecture

```
┌─────────────┐     Scan QR     ┌─────────────┐
│  Phone App  │ ─────────────► │   Server    │
│             │   (QUIC conn)   │  + Terminal  │
└─────────────┘                 └─────────────┘
```

## Development

```bash
# Build
cargo build --release

# Run tests
cargo test

# With debug logging
RUST_LOG=debug cargo run --bin hostagent
```

## Documentation

- [Architecture](docs/system-architecture.md)
- [Roadmap](docs/project-roadmap.md)
- [Code Standards](docs/code-standards.md)

## License

MIT
