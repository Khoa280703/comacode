# Tech Stack

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter UI Layer                        │
│                  (iOS + Android Frontend)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │ flutter_rust_bridge
                       │ ~100ns overhead, zero-copy
┌──────────────────────┴──────────────────────────────────────┐
│                    Shared Rust Core                          │
│              (Business Logic + Networking)                   │
└──────────────────────┬──────────────────────────────────────┘
                       │ QUIC Protocol
┌──────────────────────┴──────────────────────────────────────┐
│              Host Terminal (Win/Mac/Linux)                   │
│                  portable-pty + mDNS                         │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **Core Language** | Rust | Memory safety, no GC pauses, cross-platform compilation |
| **Mobile Bridge** | flutter_rust_bridge v2 | Production-ready, ~100ns overhead, zero-copy deserialization |
| **Network Protocol** | QUIC (quinn) | 0-RTT connection, HOL blocking elimination, connection migration |
| **Terminal Emulation** | portable-pty | Cross-platform PTY (Windows/macOS/Linux), battle-tested by WezTerm |
| **Serialization** | Postcard | Binary format, zero-copy deserialize, no schema compilation |
| **Service Discovery** | mDNS (mdns-sd) | Zero-config LAN discovery, native OS support |
| **Frontend UI** | Flutter + xterm.dart | 60fps rendering, cross-platform, rich terminal emulation |

## Platform Support

### Client (Flutter)
- **iOS**: 12.0+
- **Android**: API 21+ (Android 5.0)

### Host (Rust Binary)
- **Windows**: 10+ (msvc)
- **macOS**: 10.14+ (M1 + Intel)
- **Linux**: glibc 2.17+ (Ubuntu 18.04+, RHEL 8+)

## Design Tokens

```yaml
colors:
  background: "#1E1E2E"    # Catppuccin Mocha Base
  foreground: "#CDD6F4"    # Catppuccin Mocha Text
  primary: "#C678DD"       # Purple (accent)
  secondary: "#98C379"     # Green (success)
  error: "#E06C75"         # Red (error)
  warning: "#E5C07B"       # Yellow (warning)

typography:
  font_family: "JetBrains Mono" or "Fira Code"
  font_size:
    terminal: 14px
    ui_text: 16px
    code: 13px

spacing:
  unit: 8px
  padding_small: 8px
  padding_medium: 16px
  padding_large: 24px
```

## Trade-offs

### Acceptable Costs
| Impact | Description | Mitigation |
|--------|-------------|------------|
| **Build Time** | +10-60s for FRB codegen | Incremental builds, parallel compilation |
| **App Size** | +2-5MB embedded Rust | Strip symbols, optimize binary size |
| **Debugging** | Complex FFI boundary | FRB logging, separate unit tests |

### Rejected Alternatives

| Decision | Alternative | Why Rejected |
|----------|-------------|--------------|
| Rust over Swift/Kotlin | Separate native codebases | 2x development effort, fragmented business logic |
| QUIC over TCP/WebSocket | Legacy protocols | HOL blocking, higher latency, poor mobile network support |
| Postcard over serde_json | JSON format | 2-3x larger payload, parse overhead on mobile |
| flutter_rust_bridge over Pigeon | Dart-only FFI | Limited to Dart, poor Rust async support |

## Performance Targets

- **Latency**: <16ms frame time (60fps)
- **Startup**: <500ms cold start
- **Memory**: <50MB per connection
- **Battery**: Background <2% CPU idle

## Security Considerations

- **FFI Boundary**: Memory-safe Rust, no raw pointers exposed to Dart
- **Network**: QUIC TLS 1.3 mandatory, certificate pinning
- **Authentication**: Ed25519 key pairs, mDNS hostname verification
- **Terminal**: PTY sandboxing, no shell escape

## Development Workflow

```bash
# Rust core
cd core && cargo build --release

# Flutter bridge
cd mobile && flutter pub run build_runner build --delete-conflicting-outputs

# Integrated app
cd mobile && flutter run
```

## References

- Research reports: `plans/reports/planner-260106-*`
- flutter_rust_bridge: https://cjycode.com/flutter_rust_bridge/
- Quinn QUIC: https://github.com/quinn-rs/quinn
- portable-pty: https://github.com/wez/wezterm/tree/master/crates/pty
