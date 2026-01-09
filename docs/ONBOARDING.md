# Comacode - Developer Onboarding Guide

**Version:** 0.1.0-mvp
**Last Updated:** 2026-01-09
**Phase:** Phase 04.1 - QUIC Client Complete

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Environment Setup](#4-environment-setup)
5. [Project Structure](#5-project-structure)
6. [Development Workflow](#6-development-workflow)
7. [Code Conventions](#7-code-conventions)
8. [Testing](#8-testing)
9. [Debugging](#9-debugging)
10. [Deployment](#10-deployment)
11. [Troubleshooting](#11-troubleshooting)
12. [Resources](#12-resources)

---

## 1. Project Overview

### What is Comacode?

**Comacode** là ứng dụng terminal remote cho phép điều khiển desktop terminal từ điện thoại sử dụng giao thức QUIC.

**Key Features:**
- Remote terminal access từ mobile → desktop
- QUIC protocol (TLS 1.3) cho transport security
- TOFU (Trust On First Use) cho certificate verification
- QR code pairing cho thiết lập ban đầu
- Real-time terminal output streaming

### Use Cases

- Sysadmin cần check server khi không có laptop
- Developer cần chạy commands từ xa
- Quick server monitoring via mobile

### Project Status

| Component | Status | Notes |
|-----------|--------|-------|
| Rust Backend | 90% | Core logic done, optimization pending |
| Host Agent | 100% | QUIC server, PTY manager working |
| Mobile Bridge | 85% | FFI done, stream I/O stubs pending |
| Flutter App | 30% | Basic structure, UI pending |
| iOS Build | 80% | Framework linking works, polishing needed |

---

## 2. Architecture

### System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Mobile Device (iOS/Android)              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Flutter UI Layer                        │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │Discovery │  │ Terminal │  │ Settings  │          │   │
│  │  └─────┬────┘  └─────┬────┘  └─────┬─────┘          │   │
│  │        └───────────────┴───────────────┘             │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │       Flutter Rust Bridge (FRB v2.4)         │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └──────────────────────┬─────────────────────────────┘   │
│                         │ FFI Boundary                      │
│  ┌──────────────────────▼─────────────────────────────┐   │
│  │              Rust FFI Bridge Layer                  │   │
│  │  ┌──────────────────────────────────────────────┐  │   │
│  │  │  QuicClient + TofuVerifier                   │  │   │
│  │  └──────────────────────────────────────────────┘  │   │
│  └──────────────────────┬─────────────────────────────┘   │
└─────────────────────────┼─────────────────────────────────┘
                          │ QUIC (UDP) + TLS 1.3
┌─────────────────────────▼─────────────────────────────────┐
│                    Desktop Machine (Host Agent)            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  QUIC Server + PTY Manager + Certificate Manager    │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │  │
│  │  │Session   │  │PTY       │  │Certificate       │  │  │
│  │  │Manager   │  │Manager   │  │Manager           │  │  │
│  │  └──────────┘  └─────┬────┘  └──────────────────┘  │  │
│  │                      │                               │  │
│  │               ┌──────▼──────┐                        │  │
│  │               │Shell Process│                        │  │
│  │               │(zsh/bash)   │                        │  │
│  │               └─────────────┘                        │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

#### Connection Flow

```
Mobile                    Host
  │                         │
  │ 1. Scan QR code         │
  │    (ip, port, fp, token)│
  │                         │
  │ 2. QUIC connect ───────>│
  │                         │
  │ 3. TLS handshake ──────>│
  │<────────────────────────│
  │                         │
  │ 4. Verify fingerprint   │
  │    (TOFU)               │
  │                         │
  │ 5. Send auth token ────>│
  │                         │
  │    Validate token ──────│
  │                         │
  │ 6. Connection ready     │
```

#### Terminal I/O Flow

```
Keystroke (Mobile)           Input (Host)
     │                            │
     ├─> xterm_flutter            │
     ├─> FRB bridge               │
     ├─> QuicClient              │
     ├─> QUIC network ───────────>│
     │                            ├─> QUIC Server
     │                            ├─> Session Manager
     │                            ├─> PTY Manager
     │                            └─> Shell Process
     │                            │
     │<───────── Output ──────────┤
     │                            │
  PTY Output                   Shell writes to PTY
     │                            │
  <Display on mobile>
```

### Security Layers

1. **Transport**: TLS 1.3 (QUIC) - AES-256-GCM encryption
2. **Certificate**: Self-signed với SHA256 fingerprint
3. **TOFU**: Trust On First Use - first connection via QR (physical proximity)
4. **Auth Token**: 256-bit cryptographically secure random token
5. **Storage**: Keychain (iOS) / Keystore (Android)

---

## 3. Technology Stack

### Rust Workspace

| Crate | Purpose | Key Dependencies |
|-------|---------|------------------|
| `core` | Shared types, protocol | serde, postcard, tokio |
| `hostagent` | Desktop server | quinn 0.11, rustls 0.23, portable-pty |
| `mobile_bridge` | Flutter FFI | flutter_rust_bridge 2.4, quinn |
| `cli_client` | Testing CLI | tokio, quinn |

### Flutter App

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_rust_bridge | 2.4+ | FFI bindings generator |
| xterm_flutter | 2.0+ | Terminal emulator widget |
| mobile_scanner | 3.5+ | QR code scanner |
| flutter_secure_storage | 9.0+ | Secure credentials storage |
| flutter_riverpod | - | State management |

---

## 4. Environment Setup

### Prerequisites

**Common:**
- Git
- Rust 1.75+ (via rustup)
- Node.js 18+ (for web UI)

**macOS:**
- Xcode 15+ (for iOS development)
- CocoaPods
- iOS Device/Simulator

**Linux:**
- build-essential
- clang

**Windows:**
- Visual Studio Build Tools
- Windows Terminal

### Step 1: Clone & Setup

```bash
# Clone repository
git clone https://github.com/yourusername/comacode.git
cd comacode

# Install Rust toolchains
rustup target add aarch64-apple-ios  # iOS
rustup target add aarch64-linux-android  # Android
rustup target add x86_64-unknown-linux-gnu  # Desktop Linux

# Install Flutter (if not installed)
flutter --version
flutter doctor
```

### Step 2: Build Rust Components

```bash
# Build all workspace members
cargo build --release

# Build for iOS
cargo build --release --target aarch64-apple-ios

# Build for Android
cargo build --release --target aarch64-linux-android
```

### Step 3: Setup Flutter App

```bash
cd mobile

# Install dependencies
flutter pub get

# Generate FFI bindings (after Rust code changes)
flutter_rust_bridge_codegen --rust-input ../crates/mobile_bridge/src/api.rs \
  --dart-output ./lib/bridge/frb_generated.dart

# Run on connected device
flutter run
```

### Step 4: Run Host Agent

```bash
# Run host agent (desktop server)
cargo run --bin hostagent

# Or with custom port
cargo run --bin hostagent -- --port 8443

# Show QR code for pairing
cargo run --bin hostagent -- --qr
```

### IDE Setup

**VSCode Extensions:**
- rust-analyzer
- Flutter
- Dart
- CodeLLDB (debugger)
- TOML

**IDEA/CLion:**
- Rust plugin
- Flutter plugin

---

## 5. Project Structure

```
Comacode/
├── crates/                          # Rust workspace
│   ├── core/                        # Shared library
│   │   ├── src/
│   │   │   ├── types/               # Message types
│   │   │   │   ├── message.rs       # NetworkMessage enum
│   │   │   │   ├── event.rs         # TerminalEvent
│   │   │   │   └── auth.rs          # AuthToken
│   │   │   ├── transport/           # Network layer
│   │   │   │   ├── mod.rs
│   │   │   │   └── stream.rs        # Stream utilities
│   │   │   ├── protocol/            # Message codec
│   │   │   │   └── codec.rs
│   │   │   ├── error.rs             # Error types
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   ├── hostagent/                   # Desktop server
│   │   ├── src/
│   │   │   ├── main.rs              # CLI entry
│   │   │   ├── quic_server.rs       # QUIC server
│   │   │   ├── pty.rs               # PTY manager
│   │   │   ├── cert.rs              # Certificate manager
│   │   │   ├── auth.rs              # Auth + rate limiting
│   │   │   ├── session.rs           # Session management
│   │   │   └── web_ui.rs            # Web dashboard
│   │   └── Cargo.toml
│   │
│   ├── mobile_bridge/               # Flutter FFI
│   │   ├── src/
│   │   │   ├── lib.rs               # FFI exports
│   │   │   ├── api.rs               # flutter_rust_bridge
│   │   │   └── quic_client.rs       # QUIC client
│   │   └── Cargo.toml
│   │
│   └── cli_client/                  # CLI for testing
│       ├── src/
│       │   ├── main.rs
│       │   └── message_reader.rs
│       └── Cargo.toml
│
├── mobile/                          # Flutter app
│   ├── lib/
│   │   ├── main.dart                # App entry
│   │   ├── core/
│   │   │   └── theme.dart           # Catppuccin theme
│   │   ├── bridge/
│   │   │   └── frb_generated.dart   # Generated FFI
│   │   └── features/
│   │       ├── connection/          # Connection UI
│   │       ├── qr_scanner/          # QR scanner
│   │       └── terminal/            # Terminal UI
│   ├── ios/
│   │   ├── Runner.xcodeproj/
│   │   ├── Runner/
│   │   └── Frameworks/              # Rust framework
│   ├── android/
│   └── pubspec.yaml
│
├── docs/                            # Documentation
│   ├── ONBOARDING.md                # This file
│   ├── project-overview-pdr.md      # Product requirements
│   ├── system-architecture.md       # Architecture details
│   └── ...
│
├── plans/                           # Development plans
│   └── 260106-2127-comacode-mvp/
│       ├── phase-01-project-setup.md
│       ├── phase-02-rust-core.md
│       └── ...
│
├── Cargo.toml                       # Workspace root
├── Cargo.lock
└── README.md
```

---

## 6. Development Workflow

### Making Changes

#### Rust Code Changes

```bash
# 1. Edit Rust code
vim crates/mobile_bridge/src/api.rs

# 2. Re-generate Flutter bindings
cd mobile
flutter_rust_bridge_codegen \
  --rust-input ../crates/mobile_bridge/src/api.rs \
  --dart-output ./lib/bridge/frb_generated.dart

# 3. Rebuild Rust library
cd ../crates/mobile_bridge
cargo build --release --target aarch64-apple-ios

# 4. Copy framework to iOS project
# (Manual or via build script)

# 5. Run Flutter app
cd ../../mobile
flutter run
```

#### Flutter Code Changes

```bash
# Hot reload works for Dart changes only
cd mobile
flutter run

# Make changes, press:
# r - Hot reload
# R - Hot restart
# q - Quit
```

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/terminal-ui

# Commit changes
git add .
git commit -m "feat: add terminal output display"

# Push to remote
git push origin feature/terminal-ui

# Create PR
```

### Commit Convention

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:** feat, fix, docs, style, refactor, test, chore

**Examples:**
- `feat: add QR code scanner`
- `fix: handle TOFU fingerprint mismatch`
- `docs: update architecture diagram`

---

## 7. Code Conventions

### Rust

**Style:**
- Use `cargo fmt` before commit
- Use `cargo clippy` for linting
- 4 spaces indentation
- Prefer `&str` over `String` for function params

**Error Handling:**
```rust
// Use Result for fallible operations
pub async fn connect(&mut self, host: &str) -> Result<()> {
    let addr = format!("{}:{}", host, self.port).parse()?;
    // ...
}

// Use thiserror for custom errors
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConnectError {
    #[error("Connection failed: {0}")]
    Io(#[from] std::io::Error),
}
```

**Async:**
```rust
// Use tokio for async
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub async fn read_loop(&mut self) -> Result<()> {
    let mut buf = [0u8; 4096];
    loop {
        let n = self.stream.read(&mut buf).await?;
        if n == 0 { return Ok(()); }
        // process
    }
}
```

### Dart/Flutter

**Style:**
- Use `dart format` before commit
- Use `flutter analyze` for static analysis
- 2 spaces indentation

**State Management:**
```dart
// Using Riverpod
final terminalProvider = StateNotifierProvider<TerminalNotifier, TerminalState>((ref) {
  return TerminalNotifier();
});

class TerminalNotifier extends StateNotifier<TerminalState> {
  TerminalNotifier() : super(TerminalState.initial());

  void connect(String host, int port) async {
    state = state.copyWith(isLoading: true);
    try {
      await rustLib.connect(host, port);
      state = state.copyWith(isConnected: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
```

---

## 8. Testing

### Rust Tests

```bash
# Run all tests
cargo test

# Run specific crate tests
cargo test -p mobile_bridge

# Run with output
cargo test -- --nocapture

# Run specific test
cargo test test_tofu_verify
```

### Flutter Tests

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/

# Run with coverage
flutter test --coverage
```

### Manual Testing

```bash
# Terminal 1: Start host agent
cargo run --bin hostagent -- --port 8443

# Terminal 2: Connect with CLI client
cargo run --bin cli_client -- --host localhost --port 8443

# Terminal 3: Run mobile app
cd mobile && flutter run
```

---

## 9. Debugging

### Rust Debugging

```bash
# Build with debug symbols
cargo build

# Use lldb (macOS)
lldb target/debug/hostagent
(lldb) breakpoint set --name main
(lldb) run

# Use rust-gdb (Linux)
rust-gdb target/debug/hostagent
```

### Flutter Debugging

```bash
# Run with verbose logging
flutter run -v

# Debug on device
flutter run --debug

# Observatory debugger
flutter run --profile
```

### Logging

**Rust:**
```rust
use tracing::{info, warn, error, debug};

// Initialize tracing
tracing_subscriber::fmt::init();

// Use in code
info!("Connecting to {}:{}", host, port);
warn!("Certificate fingerprint mismatch");
error!("Connection failed: {}", err);
```

**Dart:**
```dart
import 'package:flutter/foundation.dart';

// Use debugPrint for logging
debugPrint('Connecting to $host:$port');

// Or use logging package
import 'package:logging/logging';

final log = Logger('Comacode');
log.info('Connection established');
```

---

## 10. Deployment

### iOS Build

```bash
cd mobile/ios

# Archive for distribution
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath Runner.xcarchive \
  archive

# Export IPA
xcodebuild -exportArchive \
  -archivePath Runner.xcarchive \
  -exportPath build/ios \
  -exportOptionsPlist ExportOptions.plist
```

### Android Build

```bash
cd mobile/android

# Build APK
./gradlew assembleRelease

# Build App Bundle
./gradlew bundleRelease
```

### Host Agent Release

```bash
# Build release binary
cargo build --release --bin hostagent

# Cross-compile for targets
cargo build --release --bin hostagent --target x86_64-unknown-linux-gnu
cargo build --release --bin hostagent --target x86_64-pc-windows-msvc
cargo build --release --bin hostagent --target aarch64-apple-darwin
```

---

## 11. Troubleshooting

### iOS Build Issues

**Framework not found:**
```bash
# Rebuild framework
cargo build --release --target aarch64-apple-ios
lipo -create \
  target/aarch64-apple-ios/release/libmobile_bridge.a \
  -output ios/Frameworks/mobile_bridge.framework/mobile_bridge
```

**Code signing issues:**
```bash
# Check provisioning profile
security find-identity -v -p codesigning

# Fix framework signature
codesign --force --sign - \
  ios/Frameworks/mobile_bridge.framework
```

### Flutter Issues

**FRB bindings outdated:**
```bash
# Regenerate bindings
flutter_rust_bridge_codegen \
  --rust-input ../crates/mobile_bridge/src/api.rs \
  --dart-output ./lib/bridge/frb_generated.dart
```

**Hot reload not working:**
- Hot reload only works for Dart changes
- Rust changes require full rebuild

### Connection Issues

**Certificate fingerprint mismatch:**
```bash
# Clear saved credentials (iOS)
# Delete app from device

# Generate new certificate on host
cargo run --bin hostagent -- --qr
```

**Port already in use:**
```bash
# Find process using port
lsof -i :8443

# Kill process
kill -9 <PID>
```

---

## 12. Resources

### Internal Documentation

- [Product Requirements](./project-overview-pdr.md)
- [System Architecture](./system-architecture.md)
- [Codebase Summary](./codebase-summary.md)
- [Tech Stack](./tech-stack.md)
- [Development Roadmap](./project-roadmap.md)

### External Resources

- [Quinn QUIC Documentation](https://docs.rs/quinn/)
- [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/)
- [xterm.dart](https://pub.dev/packages/xterm_flutter)
- [Rust Async Book](https://rust-lang.github.io/async-book/)

### Team Communication

- GitHub Issues: Bug reports, feature requests
- GitHub Discussions: Q&A, design discussions
- Daily Standup: Progress updates

---

## Quick Reference

### Essential Commands

```bash
# Host agent
cargo run --bin hostagent -- --port 8443 --qr

# Flutter app
cd mobile && flutter run

# Build iOS framework
cargo build --release --target aarch64-apple-ios

# Regenerate FRB
flutter_rust_bridge_codegen \
  --rust-input ../crates/mobile_bridge/src/api.rs \
  --dart-output ./lib/bridge/frb_generated.dart

# Run tests
cargo test
flutter test

# Format code
cargo fmt
dart format .
```

### File Locations

| What | Where |
|------|-------|
| Network protocol | `crates/core/src/types/message.rs` |
| QUIC client | `crates/mobile_bridge/src/quic_client.rs` |
| QUIC server | `crates/hostagent/src/quic_server.rs` |
| PTY manager | `crates/hostagent/src/pty.rs` |
| FFI bindings | `mobile/lib/bridge/frb_generated.dart` |
| Terminal UI | `mobile/lib/features/terminal/` |

---

**Happy Coding! 🚀**

For questions, reach out to the team via GitHub Discussions or create an issue.
