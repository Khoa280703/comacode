---
title: "Phase 01: Project Setup & Tooling"
description: "Initialize monorepo structure, CI/CD, dev tools for Comacode"
status: completed
priority: P0
effort: 4h
branch: main
tags: [setup, tooling, ci-cd]
created: 2026-01-06
completed: 2026-01-06
---

# Phase 01: Project Setup & Tooling

## Context
- [Parent Plan](./plan.md)
- Original [Idea](../../idea.md)

## Overview
Bootstrap development environment with monorepo structure, tooling, and CI/CD pipeline.

## Key Insights
- Monorepo enables shared Rust code across mobile/host
- FRB requires specific project layout
- CI/CD catches cross-platform issues early

## Requirements
- Monorepo with workspace structure
- Rust toolchain (stable, nightly for FRB)
- Flutter SDK (stable channel)
- CI/CD (GitHub Actions)
- Pre-commit hooks
- Local development scripts

## Architecture
```
comacode/
├── crates/              # Rust workspace
│   ├── core/           # Shared logic
│   ├── host_agent/     # PC binary
│   └── mobile_bridge/  # Flutter FFI
├── mobile/             # Flutter app
├── scripts/            # Dev utilities
├── docs/               # Architecture docs
└── .github/            # CI/CD
```

## Implementation Steps

### Step 1: Initialize Monorepo (1h)
```bash
# Root Cargo.toml with workspace
[workspace]
members = ["crates/*"]
resolver = "2"

# Create crate directories
mkdir -p crates/{core,host_agent,mobile_bridge}
```

**Tasks**:
- [ ] Create root `Cargo.toml` with workspace config
- [ ] Initialize each crate with `cargo new`
- [ ] Set up Flutter app: `flutter create mobile --platforms ios,android`
- [ ] Create `.gitignore` for Rust + Flutter

### Step 2: Configure Rust Toolchain (30m)
```toml
# rust-toolchain.toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy", "rust-src"]
```

**Tasks**:
- [ ] Add `rust-toolchain.toml`
- [ ] Configure `cargo/config.toml` for build optimizations
- [ ] Set up `justfile` or `Makefile` for common commands

### Step 3: flutter_rust_bridge Setup (1h)
```bash
# Install FRB CLI
cargo install flutter_rust_bridge_codegen

# Initialize bridge in mobile_bridge crate
cd crates/mobile_bridge
flutter_rust_bridge_init --default-enum-type=新类型模式
```

**Tasks**:
- [ ] Add FRB dependencies to `mobile_bridge/Cargo.toml`
- [ ] Create initial `api.rs` with FFI bridge
- [ ] Generate Dart bindings: `flutter_rust_bridge_codegen --rust-input ./crates/mobile_bridge/src/api.rs --dart-output ./mobile/lib/bridge_generated.dart`
- [ ] Test basic FFI call (e.g., `add_numbers(a, b)`)

### Step 4: CI/CD Pipeline (1h)
```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  rust-test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --workspace

  flutter-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: cd mobile && flutter test
```

**Tasks**:
- [ ] Create GitHub Actions workflow for Rust (all platforms)
- [ ] Create workflow for Flutter (lint + test)
- [ ] Add FRB codegen step to CI
- [ ] Set up automated builds for host_agent binary

### Step 5: Pre-commit Hooks (30m)
```bash
# Install pre-commit
pip install pre-commit

# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: rust-fmt
        name: Rust Format
        entry: cargo fmt
        language: system
      - id: flutter-fmt
        name: Flutter Format
        entry: flutter format .
        language: system
```

**Tasks**:
- [ ] Configure pre-commit for Rust (fmt, clippy)
- [ ] Configure pre-commit for Flutter (format, analyze)
- [ ] Add git hook to run before push

## Todo List
- [ ] Create workspace Cargo.toml
- [ ] Initialize 3 Rust crates
- [ ] Set up Flutter project
- [ ] Install and configure FRB
- [ ] Create first FFI bridge function
- [ ] Set up GitHub Actions CI
- [ ] Configure pre-commit hooks
- [ ] Write development documentation
- [ ] Test build on all target platforms

## Success Criteria
- `cargo build --workspace` succeeds
- `flutter test` passes
- FRB generates valid Dart bindings
- CI runs successfully on all platforms
- Pre-commit hooks enforce formatting

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| FRB version conflict | Medium | Medium | Pin versions in Cargo.lock |
| Flutter environment issues | Low | Low | Document setup steps clearly |
| Windows CI failures | Medium | Medium | Test on Windows dev machine first |

## Security Considerations
- No secrets in repo (use GitHub Secrets)
- Signed commits (GPG)
- Dependabot for dependency updates
- SBOM generation for Rust binaries

## Related Code Files
- `/Cargo.toml` - Workspace config
- `/rust-toolchain.toml` - Toolchain pinning
- `/crates/*/Cargo.toml` - Crate configs
- `/.github/workflows/*.yml` - CI/CD
- `/mobile/pubspec.yaml` - Flutter deps

## Next Steps
Once complete, proceed to [Phase 02: Rust Core](./phase-02-rust-core.md) to build shared business logic.

## Resources
- [flutter_rust_bridge docs](https://cjycode.com/)
- [Rust workspace guide](https://doc.rust-lang.org/book/ch14-03-cargo-workspaces.html)
- [Flutter CI best practices](https://docs.flutter.dev/deployment/cd#github-actions)
