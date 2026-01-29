# Comacode

> **"Vibe Coding" từ xa qua QR code** - Remote terminal with chat-style interface

Quét QR → Kết nối ngay → Chat-style terminal với multi-session

## Bắt đầu nhanh

```bash
# Khởi chạy host agent
cargo run -p hostagent -- --qr-terminal

# Quét QR bằng app điện thoại → Đã kết nối
```

## Mục lục

- [Tính năng](#tính-năng)
- [Kiến trúc](#kiến-trúc)
- [Cấu trúc dự án](#cấu-trúc-dự-án)
- [Thiết lập development](#thiết-lập-development)
- [Chạy local](#chạy-local)
- [Thiết lập Mobile App](#thiết-lập-mobile-app)
- [Hướng dẫn build iOS](#hướng-dẫn-build-ios)
- [Testing](#testing)
- [Xử lý sự cố](#xử-lý-sự-cố)
- [Tài liệu](#tài-liệu)

---

## Tính năng

### Vibe Coding Interface ✅
- Chat-style terminal với multi-tab (max 5 sessions)
- Output parsing thông minh (file, diff, error, question, list, plan, code block)
- Speech input support
- Output search với case-sensitive toggle
- Raw/Parsed mode toggle
- File attachment support
- Haptic feedback

### Multi-Session Management ✅
- Project/session organization với persistence
- Re-attach/re-spawn logic (session restoration sau app restart)
- TaggedOutput pump integration (backend multi-session streaming)
- VFS integration cho project path selection
- Session switching trong realtime

### Terminal Access
- Real-time terminal output qua QUIC protocol
- Virtual key bar (ESC, CTRL, TAB, Arrow keys)
- Catppuccin Mocha theme
- Screen wakelock toggle
- Font size adjustment (11-16px)

### Security
- TOFU (Trust On First Use) fingerprint verification
- 256-bit AuthToken for authentication
- Secure credential storage (Keychain/Keystore)
- Rate limiting cho authentication attempts
- TLS 1.3 with forward secrecy

### Virtual File System (VFS)
- Directory listing với metadata
- Chunked streaming (150 entries/chunk, max 10,000)
- Path traversal protection
- File watcher với push events
- Sorted entries (directories first)

---

## Kiến trúc

```
┌─────────────────┐    QUIC/TLS    ┌─────────────────┐
│   Flutter App   │  ───────────►   │   Host Agent    │
│   (iOS/13.0+)   │  (encrypted)    │   (Rust)        │
│                 │                 │                 │
│  - Vibe Client  │                 │  - QUIC Server  │
│  - Multi-Session│                 │  - PTY Manager  │
│  - VFS Browser  │                 │  - VFS Module   │
│  - QR Scanner   │                 │  - Web Dashboard │
└─────────────────┘                 │  - Session Mgr  │
                                      └────────┬────────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │   System Shell  │
                                      └─────────────────┘
```

**Protocol Stack:**
- QUIC (quinn 0.11) → UDP transport
- rustls 0.23 → TLS 1.3 encryption
- Custom protocol → Terminal events/messages
- Postcard → Binary serialization

---

## Cấu trúc dự án

```
Comacode/
├── crates/                    # Rust workspace (4 crates)
│   ├── core/                  # Shared types, protocol, transport
│   ├── hostagent/             # Binary server (QUIC, PTY, VFS, Session)
│   ├── mobile_bridge/         # FFI bridge (QUIC client)
│   └── cli_client/            # CLI client (SSH-like)
├── mobile/                    # Flutter app
│   ├── ios/                   # iOS native code & framework
│   └── lib/
│       ├── core/              # Theme, storage
│       ├── bridge/            # FFI bindings
│       └── features/          # Vibe, Project, Connection, VFS, QR
├── docs/                      # Documentation
└── plans/                     # Implementation plans
```

---

## Thiết lập Development

### Yêu cầu

```bash
# Rust (via rustup)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.io | sh

# Flutter
# Download từ https://flutter.dev/docs/get-started/install
flutter doctor

# iOS development (chỉ macOS)
# Cài Xcode từ App Store
sudo xcode-select --switch /Applications/Xcode.app

# Rust targets thêm cho iOS
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
```

### Clone & Setup

```bash
# Clone repository
git clone <repo-url>
cd Comacode

# Cài dependencies
cargo build
```

---

## Chạy Local

### Host Agent (Server)

```bash
# Chạy với QR trong terminal
cargo run --bin hostagent -- --qr-terminal

# Chạy với web dashboard (mở browser)
cargo run --bin hostagent --

# Bind address tùy chỉnh
cargo run --bin hostagent -- --bind 0.0.0.0:8443

# Với debug logging
RUST_LOG=debug cargo run --bin hostagent -- --qr-terminal
```

**Options có sẵn:**
| Flag | Mô tả |
|------|-------|
| `--bind <addr>` | Bind address (mặc định: `0.0.0.0:8443`) |
| `--log-level` | Log level (mặc định: `info`) |
| `--qr-terminal` | Hiện QR trong terminal thay vì web |
| `--no-browser` | Không tự mở web dashboard |

---

## Build Commands

### Backend (Rust)

```bash
# Development build
cargo build

# Release build
cargo build --release

# Chạy host agent với QR
cargo run --bin hostagent -- --qr-terminal
```

### Flutter (iOS)

```bash
cd mobile

# Get dependencies
flutter pub get

# Debug build (simulator)
flutter run

# Release build cho device
flutter build ios --release

# Archive và export (via Xcode)
open ios/Runner.xcworkspace
# Xcode → Product → Archive
```

### Full iOS Build Workflow

```bash
# 1. Build Rust library (device)
cargo build --release --target aarch64-apple-ios --package mobile_bridge

# 2. Copy binary
cp target/aarch64-apple-ios/release/libmobile_bridge.a \
   mobile/ios/Frameworks/libmobile_bridge.a

# 3. Code sign
codesign --force --sign - mobile/ios/Frameworks/libmobile_bridge.a

# 4. Build Flutter app
cd mobile
flutter build ios --release
```

---

## Thiết lập Mobile App

### Cài Flutter Dependencies

```bash
cd mobile
flutter pub get
```

### Chạy trên iOS Simulator

```bash
flutter devices  # Tìm simulator ID
flutter run -d <simulator-id>
```

### Chạy trên thiết bị thật

```bash
# Kết iPhone qua USB
flutter devices
flutter run -d <device-id>
```

---

## Hướng dẫn build iOS

**Quan trọng:** iOS cần bundled Rust library thành framework.

### Bước 1: Build Rust Library cho iOS

```bash
# Cho device thật
cargo build --release --target aarch64-apple-ios --package mobile_bridge

# Cho simulator
cargo build --release --target aarch64-apple-ios-sim --package mobile_bridge
```

### Bước 2: Copy Binary vào Framework

```bash
# Device binary
cp target/aarch64-apple-ios/release/libmobile_bridge.a \
   mobile/ios/Frameworks/libmobile_bridge.a

# Code sign
codesign --force --sign - mobile/ios/Frameworks/libmobile_bridge.a
```

### Bước 3: Build iOS App

```bash
# Qua Xcode (khuyến nghị)
open mobile/ios/Runner.xcworkspace
# Nhấn Cmd+R để build và run

# Hoặc qua Flutter
flutter run
```

---

## Testing

```bash
# Rust unit tests
cargo test --workspace

# Flutter tests (developer handles manually)
flutter test  # Run by developer only
```

**Note**: Flutter testing được developer xử lý manual (xem [code-standards.md](docs/code-standards.md)).

---

## Xử lý sự cố

| Issue | Giải pháp |
|-------|-----------|
| Client already initialized | Gọi `disconnect_from_host()` trước khi reconnect |
| CryptoProvider panic | Thêm `features = ["ring"]` vào rustls dependency |
| iOS framework not found | Kiểmtra Build Phases → Link Binary With Libraries |
| QUIC connection timeout | Kiểm tra firewall, IP/port, certificate fingerprint |

Xem thêm troubleshooting trong [docs/](docs/).

---

## Tài liệu

- [Tổng quan dự án & PDR](docs/project-overview-pdr.md)
- [Kiến trúc hệ thống](docs/system-architecture.md)
- [Lộ trình dự án](docs/project-roadmap.md)
- [Tiêu chuẩn code](docs/code-standards.md)
- [Codebase summary](docs/codebase-summary.md)

---

## License

MIT

---

**Last Updated**: 2026-01-25
**Status**: Multi-Session Management Complete (Phases 01-07)
**Next Phase**: VFS-3 (File Operations - Read/Download)
