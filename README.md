# Comacode

> Truy cập terminal từ xa bằng QR code - Remote terminal control via QR code

Quét mã QR → Kết nối ngay → Điều khiển terminal từ điện thoại

## Bắt đầu nhanh

```bash
# Khởi chạy host agent (server)
cargo run --bin hostagent -- --qr-terminal

# Quét QR bằng app điện thoại → Đã kết nối
```

## Mục lục

- [Kiến trúc](#kiến-trúc)
- [Tính năng](#tính-năng)
- [Cấu trúc dự án](#cấu-trúc-dự-án)
- [Thiết lập development](#thiết-lập-development)
- [Chạy local](#chạy-local)
- [Thiết lập Mobile App](#thiết-lập-mobile-app)
- [Hướng dẫn build iOS](#hướng-dẫn-build-ios)
- [Testing](#testing)
- [Debug](#debug)
- [Xử lý sự cố](#xử-lý-sự-cố)

---

## Kiến trúc

```
┌─────────────────┐    QUIC/TLS    ┌─────────────────┐
│   Flutter App   │  ───────────►   │   Host Agent    │
│   (iOS/Android) │  (encrypted)    │   (Rust)        │
│                 │                 │                 │
│  - QR Scanner   │                 │  - QUIC Server  │
│  - Terminal UI  │                 │  - PTY Manager  │
│  - VFS Browser  │                 │  - VFS Module   │
│  - File Watcher │                 │  - File Watcher │
└─────────────────┘                 │  - Web Dashboard │
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

## Tính năng

### Terminal Access
- Real-time terminal output via QUIC protocol
- Virtual key bar (ESC, CTRL, TAB, Arrow keys)
- Catppuccin Mocha theme
- Screen wakelock toggle
- Font size adjustment (11-16px)

### Security
- TOFU (Trust On First Use) fingerprint verification
- 256-bit AuthToken for authentication
- Secure credential storage (Keychain/Keystore)
- Rate limiting for authentication attempts
- TLS 1.3 with forward secrecy

### Virtual File System (VFS)
- Directory listing with metadata
- Chunked streaming (150 entries/chunk, max 10,000)
- Path traversal protection
- File watcher with push events
- Sorted entries (directories first)

### Discovery
- QR code pairing (zero-config setup)
- Web dashboard with QR display
- mDNS service discovery (planned)

---

## Cấu trúc dự án

```
Comacode/
├── crates/
│   ├── core/           # Library chia sẻ (types, protocol, transport)
│   ├── hostagent/      # Binary server desktop (QUIC server, PTY, VFS)
│   ├── mobile_bridge/  # FFI bridge cho Flutter (QUIC client)
│   └── cli_client/     # CLI client binary (SSH-like terminal)
├── mobile/
│   ├── ios/            # iOS native code & framework
│   └── lib/            # Flutter app (Dart)
│       ├── core/       # Theme, storage
│       ├── bridge/     # FFI bindings
│       └── features/   # Terminal, VFS, QR scanner
├── docs/               # Tài liệu
└── plans/              # Implementation plans
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

### Unit Tests (Rust)

```bash
# Tất cả tests
cargo test

# Crate cụ thể
cargo test -p comacode-core
cargo test -p mobile_bridge

# Với output
cargo test -- --nocapture
```

### Integration Tests

```bash
# Chạy host agent với config test
cargo run --bin hostagent -- --bind 127.0.0.1:8443

# Terminal khác, chạy mobile bridge tests
cargo test -p mobile_bridge --test integration
```

---

## Debug

### Host Agent

```bash
# Bật debug logging
RUST_LOG=debug cargo run --bin hostagent -- --qr-terminal

# Trace level (chi tiết)
RUST_LOG=trace cargo run --bin hostagent --

# Module cụ thể
RUST_LOG=comacode::quic=debug cargo run --bin hostagent --
```

### Mobile Bridge (Rust)

```bash
# Xem logging cho FFI calls
RUST_BACKTRACE=1 cargo run --bin hostagent --
```

---

## Xử lý sự cố

### "Client already initialized"

**Nguyên nhân:** Static QUIC_CLIENT không được clear sau disconnect.

**Giải pháp:** Gọi `disconnect_from_host()` trước khi reconnect, hoặc restart app.

### CryptoProvider panic (rustls)

**Lỗi:** `Could not automatically determine CryptoProvider`

**Giải pháp:**
```toml
# Trong Cargo.toml
rustls = { version = "0.23", features = ["ring"] }
```

### iOS framework not found

**Kiểm tra:**
1. Framework path trong Xcode: `Build Phases → Link Binary With Libraries`
2. Framework Search Paths trong Build Settings
3. Code signature: `codesign -dv mobile/ios/Frameworks/`

### QUIC connection timeout

**Nguyên nhân có thể:**
1. Firewall chặn UDP
2. Sai IP/port trong QR code
3. Certificate fingerprint không khớp

---

## Tài liệu

- [Kiến trúc hệ thống](docs/system-architecture.md)
- [Lộ trình dự án](docs/project-roadmap.md)
- [Tiêu chuẩn code](docs/code-standards.md)
- [Tổng quan dự án](docs/project-overview-pdr.md)

---

## License

MIT
