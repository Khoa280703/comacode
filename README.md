# Comacode

> Truy cập terminal từ xa bằng QR code - Điều khiển terminal từ điện thoại

Quét mã QR → Kết nối ngay → Điều khiển terminal từ điện thoại

## Bắt đầu nhanh

```bash
# Khởi chạy host agent (server)
cargo run --bin hostagent -- --qr-terminal

# Quét QR bằng app điện thoại → Đã kết nối
```

## Mục lục

- [Kiến trúc](#kiến-trúc)
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
┌─────────────────┐    Quét QR     ┌─────────────────┐
│   Flutter App   │  ───────────►   │   Host Agent    │
│   (iOS/Android) │  (QUIC conn)    │   (Rust)        │
│                 │                 │                 │
│  - QR Scanner   │                 │  - QUIC Server  │
│  - Terminal UI  │                 │  - PTY Manager  │
└─────────────────┘                 │  - Auth System  │
                                      └─────────────────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │   System Shell  │
                                      └─────────────────┘
```

**Protocol Stack:**
- QUIC (quinn) → UDP transport
- rustls → TLS 1.3 encryption
- Custom protocol → Terminal events/messages

---

## Cấu trúc dự án

```
Comacode/
├── crates/
│   ├── core/           # Library chia sẻ (network, codec, types)
│   ├── hostagent/      # Binary server desktop
│   └── mobile_bridge/  # FFI bridge cho Flutter (Rust)
├── mobile/
│   ├── ios/            # iOS native code & framework
│   └── lib/            # Flutter app (Dart)
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
cp target/aarch64-apple-ios/release/libmobile_bridge.dylib \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

# Fix install_name (quan trọng!)
install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge

# Code sign
codesign --force --sign - mobile/ios/Frameworks/mobile_bridge.framework
```

### Bước 3: Build iOS App

```bash
# Qua Xcode (khuyến nghị)
open mobile/ios/Runner.xcworkspace
# Nhấn Cmd+R để build và run

# Hoặc qua Flutter
flutter run
```

### Lỗi build iOS thường gặp

| Lỗi | Giải pháp |
|-----|----------|
| `Framework not found` | Kiểm tra framework path trong Xcode |
| `Symbol not found` | Rebuild Rust lib với target đúng |
| `Code signing failed` | Code sign framework thủ công |
| `CryptoProvider panic` | Đảm bảo `rustls = { features = ["ring"] }` trong Cargo.toml |

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

# Test cụ thể
cargo test ten_test
```

### Integration Tests

```bash
# Chạy host agent với config test
cargo run --bin hostagent -- --bind 127.0.0.1:8443

# Terminal khác, chạy mobile bridge tests
cargo test -p mobile_bridge --test integration
```

### Flutter Tests

```bash
cd mobile

# Unit tests
flutter test

# Integration tests (cần device/emulator)
flutter test integration_test/
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

# Debug với LLDB
rust-lldb -- target/debug/hostagent
```

### Flutter App

```bash
# Flutter devtools
flutter pub global activate devtools
flutter pub global run devtools

# Attach vào app đang chạy
flutter attach
```

### Xcode (iOS)

1. Mở `mobile/ios/Runner.xcworkspace`
2. Đặt breakpoints trong Dart hoặc Swift
3. Chạy từ Xcode (Cmd+R)
4. Check console cho Rust logs qua `os_log`

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

# Trong code, gọi trước khi kết nối:
rustls::crypto::ring::default_provider().install_default();
```

### iOS framework not found

**Kiểm tra:**
1. Framework path trong Xcode: `Build Phases → Link Binary With Libraries`
2. Framework Search Paths trong Build Settings
3. Code signature: `codesign -dv mobile/ios/Frameworks/mobile_bridge.framework`

### QUIC connection timeout

**Nguyên nhân có thể:**
1. Firewall chặn UDP
2. Sai IP/port trong QR code
3. Certificate fingerprint không khớp

**Debug:**
```bash
# Test UDP connectivity
nc -uz <host> <port>

# Verify host agent đang listen
lsof -i :8443
```

---

## Development Workflow

```bash
# 1. Thay đổi code
# 2. Chạy tests
cargo test

# 3. Nếu có thay đổi Rust: rebuild iOS library
cargo build --release --target aarch64-apple-ios --package mobile_bridge
cp target/aarch64-apple-ios/release/libmobile_bridge.dylib \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
install_name_tool -id @rpath/mobile_bridge.framework/mobile_bridge \
   mobile/ios/Frameworks/mobile_bridge.framework/mobile_bridge
codesign --force --sign - mobile/ios/Frameworks/mobile_bridge.framework

# 4. Chạy Flutter app
cd mobile && flutter run

# 5. Commit khi xong
git add .
git commit -m "feat: mô tả"
```

---

## Tài liệu

- [Kiến trúc hệ thống](docs/system-architecture.md)
- [Lộ trình dự án](docs/project-roadmap.md)
- [Tiêu chuẩn code](docs/code-standards.md)
- [Hướng dẫn dev mới](docs/ONBOARDING.md)

---

## License

MIT
