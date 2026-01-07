---
title: "Phase 07: Testing & Deployment"
description: "End-to-end testing, builds, and deployment for all platforms"
status: pending
priority: P1
effort: 4h
branch: main
tags: [testing, deployment, ci-cd, builds]
created: 2026-01-06
---

# Phase 07: Testing & Deployment

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 06](./phase-06-discovery-auth.md)

## Overview
Comprehensive testing, build automation, and deployment pipeline for production-ready release.

## Key Insights
- E2E tests validate entire system
- Multi-platform testing essential
- Automated builds catch regressions
- CI/CD enables rapid iteration
- Crash reporting for production

## Requirements
- E2E integration tests
- Unit test coverage (70%+)
- Multi-platform builds
- Automated release pipeline
- Installation packages
- Documentation
- Crash reporting

## Architecture
```
Testing Pipeline
├── Unit Tests
│   ├── Rust (cargo test)
│   └── Dart (flutter test)
├── Integration Tests
│   ├── Protocol tests
│   └── FFI tests
└── E2E Tests
    ├── Real PTY
    └── Network simulation

Build Pipeline
├── Host Agent
│   ├── Windows (.exe)
│   ├── macOS (.dmg)
│   └── Linux (.deb, .tar.gz)
└── Mobile App
    ├── iOS (.ipa)
    └── Android (.apk)
```

## Implementation Steps

### Step 1: E2E Test Framework (1h)
```rust
// tests/e2e_tests.rs
use comacode_host_agent::HostAgent;
use comacode_core::types::NetworkMessage;

#[tokio::test]
async fn test_full_session() {
    // Start host agent
    let agent = HostAgent::start().await.unwrap();

    // Connect client
    let client = QuicClient::connect("localhost", 8443).await.unwrap();

    // Send command
    client.send(NetworkMessage::Command(TerminalCommand {
        text: "echo hello".into(),
        ..Default::default()
    })).await.unwrap();

    // Receive output
    let response = client.recv().await.unwrap();
    assert!(matches!(response, NetworkMessage::Event(_)));

    agent.shutdown().await.unwrap();
}
```

**Tasks**:
- [ ] Create E2E test suite
- [ ] Test host agent lifecycle
- [ ] Test client connection
- [ ] Validate command/output flow
- [ ] Test reconnection logic

### Step 2: Unit Test Coverage (1h)
```bash
# Rust tests
cargo test --workspace

# Flutter tests
flutter test --coverage

# Generate coverage report
genhtml coverage/lcov.info -o coverage/html
```

**Tasks**:
- [ ] Add unit tests for core types
- [ ] Test serialization/deserialization
- [ ] Test protocol codec
- [ ] Test PTY management
- [ ] Test UI state management
- [ ] Aim for 70%+ coverage

### Step 3: Multi-Platform Builds (1h)
```yaml
# .github/workflows/build.yml
name: Build
on: [push, pull_request]

jobs:
  host-agent:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - run: cargo build --release --bin host_agent

  mobile-app:
    strategy:
      matrix:
        target: [ios, android]
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: cd mobile && flutter build ${{ matrix.target }}
```

**Tasks**:
- [ ] Set up GitHub Actions builds
- [ ] Build host agent for all platforms
- [ ] Build iOS app (TestFlight ready)
- [ ] Build Android APK/AAB
- [ ] Sign binaries with certificates
- [ ] Generate SBOM

### Step 4: Deployment Packages (0.5h)
```bash
# Create installers
# macOS
cargo install --path crates/host_agent
mkdir -p Comacode.app/Contents/MacOS
cp target/release/host_agent Comacode.app/Contents/MacOS/

# Windows (MSIX)
cargo wix --no-build --output target/wix/comacode.msi

# Linux (deb)
cargo install cargo-deb
cargo deb --no-build
```

**Tasks**:
- [ ] Create macOS .dmg installer
- [ ] Build Windows .exe installer
- [ ] Package Linux .deb
- [ ] Create .tar.gz for Linux
- [ ] Notarize macOS binary
- [ ] Code sign Windows binary

### Step 5: Documentation (0.5h)
```markdown
# docs/user-guide.md

## Quick Start

1. Download Host Agent for your platform
2. Run: `./host-agent --port 8443`
3. Open Comacode app on phone
4. Select your host from the list
5. Enter password (default: comacode)
6. Start coding!
```

**Tasks**:
- [ ] Write user guide
- [ ] Create installation docs
- [ ] Document troubleshooting steps
- [ ] Add API documentation
- [ ] Record demo video
- [ ] Create release notes

## Todo List
- [ ] Write E2E test suite
- [ ] Add unit tests (aim 70%)
- [ ] Set up CI builds
- [ ] Create installers
- [ ] Test on real devices
- [ ] Write user documentation
- [ ] Prepare for v0.1.0 release
- [ ] Set up crash reporting (Sentry)
- [ ] Create GitHub release
- [ ] Deploy to TestFlight

## Success Criteria
- All tests pass on all platforms
- E2E tests cover happy path
- Installers work without issues
- Documentation is clear
- Demo app runs smoothly
- No critical bugs outstanding

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| macOS notarization fail | Medium | High | Test early, follow Apple guidelines |
| Windows Defender blocks | Medium | Medium | Sign binary, add to SmartScreen allowlist |
| Android permission issues | Low | Medium | Test on Android 12+ |
| iOS App Store rejection | Low | High | Review guidelines before submit |

## Security Considerations
- Code sign all binaries
- Notarize macOS builds
- Verify provenance (SBOM)
- No debug symbols in release
- Strip binaries to reduce size
- Enable hardening flags

## Related Code Files
- `/tests/e2e_tests.rs` - E2E suite
- `/.github/workflows/` - CI/CD
- `/docs/user-guide.md` - Documentation
- `/scripts/build.sh` - Build automation

## Release Checklist
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Installers tested
- [ ] Version tagged
- [ ] Release notes written
- [ ] GitHub release created
- [ ] TestFlight deployment
- [ ] Crash reporting configured

## Next Steps
After MVP release, gather feedback and plan Phase 2 features:
- File browser
- Session persistence
- Public key auth
- Relay server for remote access
- Plugin system

## Resources
- [Flutter deployment](https://docs.flutter.dev/deployment)
- [Rust packaging](https://forge.rust-lang.org/infra/packaging.html)
- [macOS notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Windows code signing](https://docs.microsoft.com/en-us/windows/win32/seccrypto/cryptography-tools)
