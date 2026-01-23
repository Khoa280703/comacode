# Comacode Project Overview & PDR

> Product Development Requirements (PDR)
> Version: 1.4 | Last Updated: 2026-01-23
> Current Phase: Phase Vibe-02 (Vibe Coding Client - Enhanced Features) Complete

---

## Executive Summary

Comacode is a **remote terminal control system** that enables mobile devices to securely connect to and control desktop terminals via QUIC protocol. The system uses TOFU (Trust On First Use) security model with certificate fingerprint verification, eliminating the need for traditional CA infrastructure while maintaining security against MitM attacks.

**Value Proposition**: Developers can control remote terminals from mobile devices with zero-friction UX, featuring QR code pairing, secure credential storage, and Catppuccin-themed terminal interface.

**Target Users**:
- Developers who need remote terminal access on-the-go
- System administrators managing servers from mobile
- DevOps engineers needing quick terminal access without laptop

---

## Product Vision

**"Zero-friction Vibe Coding from Anywhere"**

Comacode enables developers to maintain their workflow rhythm while away from their desks. Scan a QR code, connect instantly, and continue coding with full terminal capabilities - all from a mobile device with native-grade performance.

**Key Differentiators**:
1. **Instant Pairing**: QR code scanning eliminates manual configuration
2. **Native Performance**: QUIC protocol with Rust backend delivers <100ms latency
3. **Mobile-First UX**: Virtual key bar, Catppuccin theme, thumb-optimized controls
4. **Zero Infrastructure**: No cloud services, no accounts, no subscriptions

---

## Product Requirements (PDR)

### Functional Requirements

#### FR1: Terminal Access
- **FR1.1**: Mobile app must display remote terminal output in real-time
- **FR1.2**: User must be able to send commands to remote terminal
- **FR1.3**: Terminal must support standard ANSI escape sequences
- **FR1.4**: Terminal must render Catppuccin Mocha theme colors
- **FR1.5**: User must be able to adjust terminal font size (11-16px range)

#### FR2: Connection Management
- **FR2.1**: App must discover hosts via mDNS on local network (Phase 06)
- **FR2.2**: App must support QR code scanning for pairing
- **FR2.3**: App must support manual IP/port entry (fallback)
- **FR2.4**: App must auto-reconnect to last used host
- **FR2.5**: App must display connection status (scanning, connecting, connected, error)

#### FR3: Security
- **FR3.1**: Connection must use QUIC protocol over TLS 1.3
- **FR3.2**: Certificate verification must use TOFU model
- **FR3.3**: Initial pairing must require QR code scan (secure channel)
- **FR3.4**: App must validate certificate fingerprint on every connection
- **FR3.5**: App must store credentials securely (Keychain/Keystore)
- **FR3.6**: App must support 256-bit AuthToken for authentication

#### FR4: User Interface
- **FR4.1**: App must provide virtual key bar with ESC, CTRL, TAB, Arrow keys
- **FR4.2**: App must support system keyboard toggle (show/hide)
- **FR4.3**: App must support screen wakelock toggle
- **FR4.4**: App must use Catppuccin Mocha color scheme
- **FR4.5**: App must follow mobile accessibility guidelines (WCAG 2.1 AA)
- **FR4.6**: Touch targets must be minimum 48x48px

#### FR5: Session Management
- **FR5.1**: App must keep screen on during active session (wakelock)
- **FR5.2**: App must handle network disconnections gracefully
- **FR5.3**: App must allow manual disconnect
- **FR5.4**: App must support multiple saved hosts (future)

#### FR6: Virtual File System (Phase VFS-1/VFS-2) ✅
- **FR6.1**: App must request directory listing from remote host
- **FR6.2**: App must display directory entries (files/folders)
- **FR6.3**: App must support chunked responses for large directories
- **FR6.4**: App must show file metadata (size, modified time)
- **FR6.5**: App must navigate directories (parent/child)
- **FR6.6**: App must receive file watcher push events ✅ (Phase VFS-2)
- **FR6.7**: App must display VFS browser UI with navigation ✅ (Phase 06)
- **FR6.8**: App must handle empty directories (explicit empty chunk) ✅
- **FR6.9**: App must protect against path traversal attacks ✅
- **FR6.10**: App must stream chunks (150 entries/chunk, max 10,000) ✅

#### FR7: Vibe Coding Client (Phase Vibe-01/Vibe-02) ✅
- **FR7.1**: App must provide chat-style interface for Claude Code CLI ✅ (Phase Vibe-01)
- **FR7.2**: App must support session tab bar for multiple sessions ✅
- **FR7.3**: App must provide input bar with command submission ✅
- **FR7.4**: App must offer quick keys toolbar (ESC, CTRL, TAB, arrows) ✅
- **FR7.5**: App must support raw/parsed output mode toggle ✅
- **FR7.6**: App must parse terminal output into structured blocks ✅ (Phase Vibe-02)
- **FR7.7**: App must detect file paths, diffs, errors, questions in output ✅
- **FR7.8**: App must provide rich rendering for different block types ✅
- **FR7.9**: App must support collapsible blocks for plan items ✅
- **FR7.10**: App must provide search functionality in output ✅
- **FR7.11**: App must support case-sensitive search toggle ✅
- **FR7.12**: App must provide search navigation (previous/next) ✅
- **FR7.13**: App must validate paths in ReadFile handler for security ✅

---

### Non-Functional Requirements

#### NFR1: Performance
- **NFR1.1**: Connection establishment must complete within 5 seconds (local network)
- **NFR1.2**: Terminal output latency must be <100ms (local network)
- **NFR1.3**: App must support 10,000+ lines of terminal output without lag
- **NFR1.4**: App must use <100MB RAM during active session

#### NFR2: Security
- **NFR2.1**: Certificate fingerprints must be compared using constant-time algorithm
- **NFR2.2**: AuthTokens must be generated using cryptographically secure RNG
- **NFR2.3**: Sensitive data must never be logged in plaintext
- **NFR2.4**: App must pin certificate versions (prevent rollback)

#### NFR3: Reliability
- **NFR3.1**: App must handle network interruptions (auto-reconnect)
- **NFR3.2**: App must recover from crashes (restore session)
- **NFR3.3**: App must validate all user inputs before processing

#### NFR4: Compatibility
- **NFR4.1**: App must run on iOS 14+ and Android 8+ (API 26+)
- **NFR4.2**: Host agent must run on macOS 12+, Linux (glibc 2.17+)
- **NFR4.3**: App must support both IPv4 and IPv6 networks

#### NFR5: Usability
- **NFR5.1**: First-time connection must complete in <3 steps
- **NFR5.2**: Error messages must be actionable (user-understandable)
- **NFR5.3**: App must support both portrait and landscape orientations

---

## System Architecture

### High-Level Architecture

```
┌─────────────────┐         QUIC (TLS 1.3)         ┌─────────────────┐
│   Mobile App    │◄──────────────────────────────►│   Host Agent    │
│  (Flutter +     │   - Fingerprint Verification   │  (Rust + QUIC)  │
│   Rust FFI)     │   - AuthToken Validation       │                 │
│                 │   - Bidirectional Streaming    │                 │
└─────────────────┘                                 └────────┬────────┘
                                                            │
                                                            │ PTY
                                                            │
                                                      ┌─────┴─────┐
                                                      │   Shell    │
                                                      │ (zsh/bash) │
                                                      └───────────┘
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mobile App (Flutter)                     │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐  ┌─────────────┐  ┌──────────────┐             │
│ │ Discovery   │  │  Terminal   │  │  Settings    │             │
│ │   Screen    │  │    Screen   │  │   Screen     │             │
│ └──────┬──────┘  └──────┬──────┘  └──────┬───────┘             │
│        │                │                 │                      │
│ ┌──────▼────────────────▼─────────────────▼───────┐             │
│ │              ConnectionProvider                  │             │
│ │        (State Management + Secure Storage)       │             │
│ └──────────────────────────┬──────────────────────┘             │
│                             │                                     │
│ ┌──────────────────────────▼──────────────────────┐             │
│ │           Flutter Rust Bridge (FRB)             │             │
│ └──────────────────────────┬──────────────────────┘             │
└────────────────────────────┼────────────────────────────────────┘
                             │ FFI Boundary
┌────────────────────────────▼────────────────────────────────────┐
│                    Rust FFI Bridge Layer                         │
├─────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────┐        │
│ │                    QuicClient                         │        │
│ │  - connect()                                          │        │
│ │  - receive_event() (StreamSink → Flutter)            │        │
│ │  - send_command()                                     │        │
│ └──────────────────────────────────────────────────────┘        │
│ ┌──────────────────────────────────────────────────────┐        │
│ │                   TofuVerifier                        │        │
│ │  - verify_server_cert() (SHA256 fingerprint)         │        │
│ │  - normalize_fingerprint() (case-insensitive)        │        │
│ └──────────────────────────────────────────────────────┘        │
└────────────────────────────┬────────────────────────────────────┘
                             │ QUIC Protocol
┌────────────────────────────▼────────────────────────────────────┐
│                      Host Agent (Rust)                           │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐  ┌─────────────┐  ┌──────────────┐             │
│ │   QUIC      │  │     PTY     │  │  Auth Token  │             │
│ │   Server    │  │   Manager   │  │   Generator  │             │
│ └──────┬──────┘  └──────┬──────┘  └──────┬───────┘             │
│        │                │                 │                      │
│ ┌──────▼────────────────▼─────────────────▼───────┐             │
│ │              Certificate Manager                 │             │
│ │        (Self-signed cert + QR generation)        │             │
│ └──────────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

### Backend (Rust)

#### Core Libraries
| Component | Library | Version | Purpose |
|-----------|---------|---------|---------|
| QUIC Protocol | [Quinn](https://docs.rs/quinn) | 0.11 | Async QUIC implementation |
| TLS | [Rustls](https://docs.rs/rustls) | 0.23 | TLS 1.3 implementation |
| Crypto | [ring](https://docs.rs/ring) | 0.16 | Signature verification |
| Hashing | [sha2](https://docs.rs/sha2) | 0.10 | SHA256 fingerprint |
| Async | [Tokio](https://docs.rs/tokio) | 1.38 | Async runtime |
| Serialization | [Serde](https://docs.rs/serde) | 1.0 | JSON/bincode |
| Serialization | [Postcard](https://docs.rs/postcard) | 1.0 | Binary format |
| FFI | [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/) | 2.4.0 | Dart↔Rust bindings |

#### Architecture Decisions
- **QUIC vs TCP**: 1-2 RTT connection establishment (vs 3 RTT for TCP+TLS)
- **Rustls vs OpenSSL**: Memory-safe, no external dependencies, async-first
- **Tokio**: Industry-standard async runtime, excellent QUIC support
- **Postcard**: Zero-copy deserialization, optimal for FFI

### Mobile (Flutter)

#### UI Libraries
| Component | Library | Version | Purpose |
|-----------|---------|---------|---------|
| Terminal | [xterm_flutter](https://pub.dev/packages/xterm_flutter) | 2.0+ | Terminal emulation |
| QR Scanner | [mobile_scanner](https://pub.dev/packages/mobile_scanner) | 3.5.0 | Camera QR scanning |
| Secure Storage | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 9.0+ | Keychain/Keystore |
| State | [Riverpod](https://pub.dev/packages/flutter_riverpod) | 2.4.0 | State management |
| Permissions | [permission_handler](https://pub.dev/packages/permission_handler) | 11.0+ | Camera permissions |
| Wakelock | [wakelock_plus](https://pub.dev/packages/wakelock_plus) | 1.1+ | Keep screen on |

#### Architecture Decisions
- **Flutter**: Single codebase for iOS/Android, native performance (60fps)
- **xterm_flutter**: Battle-tested terminal emulator (used by VS Code)
- **Provider**: Simple, unidirectional data flow
- **Catppuccin**: Modern, accessible color scheme (WCAG AA compliant)

---

## Security Model

### TOFU (Trust On First Use)

**Concept**: Trust the server certificate on first connection, then verify fingerprint matches on subsequent connections.

**Workflow**:
```
┌─────────────────────────────────────────────────────────────┐
│ First Connection (Pairing)                                  │
├─────────────────────────────────────────────────────────────┤
│ 1. Host Agent generates self-signed certificate            │
│ 2. Host Agent displays QR code:                             │
│    {                                                         │
│      "ip": "192.168.1.1",                                   │
│      "port": 8443,                                          │
│      "fingerprint": "AA:BB:CC:DD:...",  // SHA256 hash      │
│      "token": "deadbeef...",              // AuthToken      │
│      "protocol_version": 1                                  │
│    }                                                         │
│ 3. Mobile app scans QR code                                 │
│ 4. Mobile app connects to host                              │
│ 5. Mobile app verifies fingerprint matches QR code          │
│ 6. If valid → Save to secure storage (auto-trust)           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Subsequent Connections                                      │
├─────────────────────────────────────────────────────────────┤
│ 1. Mobile app loads saved credentials                       │
│ 2. Mobile app connects to host                              │
│ 3. Host presents certificate                                │
│ 4. Mobile app calculates SHA256 fingerprint                │
│ 5. Mobile app compares with saved fingerprint               │
│ 6. If match → Connection accepted                           │
│ 7. If mismatch → Connection rejected (MitM detected)        │
└─────────────────────────────────────────────────────────────┘
```

**Risks & Mitigations**:
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| First-connection MitM | Low | High | Local network pairing, physical access |
| Fingerprint collision | Negligible | Critical | SHA256 (256-bit space) |
| Certificate expiration | Low | Medium | User warning, manual re-pairing |
| Token leakage | Low | High | Secure storage, never logged |

### AuthToken

**Purpose**: Secondary authentication layer (separate from certificate)

**Properties**:
- 256-bit cryptographically secure random value
- Generated once at Host Agent startup
- Valid until agent restarts (ephemeral)
- Validated on every connection

**Why Separate from Certificate?**
- Certificate: Long-term identity (fingerprint)
- Token: Short-term authorization (ephemeral)
- Compromise of one doesn't compromise the other

---

## Development Phases

### Phase 01: Project Setup ✅
**Status**: Complete
- Workspace structure
- CI/CD pipeline
- Linting and formatting

### Phase 02: Rust Core ✅
**Status**: Complete
- Core types (TerminalEvent, AuthToken, QrPayload)
- Shared business logic
- Serialization (Serde + Postcard)

### Phase 03: Host Agent ✅
**Status**: Complete
- QUIC server implementation
- PTY manager
- Certificate generation
- QR code display

### Phase 04: Mobile App - QUIC Client ✅
**Status**: Complete (Phase 04.1 - Critical Bugfixes Applied)

**Phase 04 Completed**:
- ✅ QUIC client with TOFU verification (Quinn 0.11 + Rustls 0.23)
- ✅ Fingerprint normalization (case-insensitive, separator-agnostic)
- ✅ AuthToken validation
- ✅ Unit tests (7 tests, all passing)
- ✅ Zero clippy warnings

**Phase 04.1 Completed** (Critical Bugfixes):
- ✅ Fixed UB in `api.rs`: Replaced `static mut QUIC_CLIENT` with `once_cell::sync::OnceCell`
  - Thread-safe initialization
  - Zero unsafe blocks
  - Proper Arc<Mutex<T>> wrapping
- ✅ Fixed fingerprint leakage in logs: Only match result logged (line 88 in quic_client.rs)

**Pending**:
- ⏳ Implement actual stream I/O (receive_event, send_command) - Currently stubs
- ⏳ Generate FRB bindings for Flutter
- ⏳ Create Flutter project
- ⏳ Implement QR scanner
- ⏳ Implement terminal UI

**Blocked**:
- ⏳ Stream I/O stubs block real Flutter integration

### Phase 05: Network Protocol (Planned)
**Status**: Not started
- Stream I/O implementation
- Bidirectional messaging
- Error handling and recovery
- Connection pooling

### Phase 06: Discovery & Auth (Planned)
**Status**: Not started
- mDNS service discovery
- Manual host entry
- Host management (save, delete, edit)
- Connection history

### Phase VFS-1: Virtual File System - Directory Listing ✅
**Status**: Complete

**Phase VFS-1 Completed**:
- ✅ VFS module implementation (`crates/hostagent/src/vfs.rs`)
- ✅ Directory listing with async I/O
- ✅ Chunked streaming (150 entries/chunk)
- ✅ Path validation with symlink resolution
- ✅ VFS message types (`ListDir`, `DirChunk`, `DirEntry`)
- ✅ VFS error types in `CoreError`
- ✅ FFI API for Flutter (`request_list_dir`, `receive_dir_chunk`)
- ✅ DirEntry getter functions

**Phase VFS-1 Features**:
- Async directory reading with `tokio::fs`
- Sorted output (directories first, alphabetically)
- Security: Path traversal protection via `canonicalize()`
- Error handling: `PathNotFound`, `PermissionDenied`, `NotADirectory`

### Phase VFS-2: Virtual File System - File Watcher ✅
**Status**: Complete

**Phase VFS-2 Completed**:
- ✅ File watcher implementation (`notify` 7.0)
- ✅ Push events for file changes
- ✅ Watcher lifecycle management
- ✅ Event propagation to client
- ✅ Empty directory handling (explicit empty chunk)

**Phase VFS-2 Features**:
- Real-time file system monitoring
- Efficient event debouncing
- Automatic re-watching on changes
- Permission checking for watched paths

**Pending**:
- ⏳ File read/download operations (Phase VFS-3)
- ⏳ File write/upload operations (Phase VFS-4)

### Phase 06: Flutter UI ✅
**Status**: Complete

**Phase 06 Completed**:
- ✅ Terminal UI with xterm_flutter
- ✅ Virtual key bar (ESC, CTRL, TAB, Arrows)
- ✅ VFS browser with navigation
- ✅ QR scanner with auto-connect
- ✅ Connection state management (Riverpod)
- ✅ Web dashboard with QR display (axum 0.7)

**Phase 06 Features**:
- Catppuccin Mocha theme
- Screen wakelock toggle
- Font size adjustment (11-16px)
- Secure credential storage
- mDNS discovery (planned)

### Phase 07: Testing & Deployment (Planned)
**Status**: Not started
- Integration tests
- E2E tests
- iOS App Store submission
- Android Play Store submission

---

## Acceptance Criteria

### Phase 04 Acceptance Criteria

#### Must Have (P0)
- [ ] App scans QR code from Host Agent
- [ ] App connects and verifies fingerprint (TOFU)
- [ ] Credentials persist in secure storage
- [ ] Terminal output streams continuously (StreamSink)
- [ ] Terminal renders in Catppuccin theme
- [ ] Virtual key bar works (ESC, CTRL, Arrows)
- [ ] App runs on iOS and Android

#### Should Have (P1)
- [ ] Keyboard toggle button (full screen view)
- [ ] Wakelock toggle button
- [ ] Screen stays on during session
- [ ] Auto-reconnect to last host
- [ ] Connection state management (loading, error)

#### Could Have (P2)
- [ ] Manual IP/port entry (fallback)
- [ ] Multiple saved hosts
- [ ] Connection history
- [ ] Font size slider (11-16px)

#### Won't Have (Out of Scope)
- File transfer
- Port forwarding
- Multiple concurrent connections
- Terminal tabs/split view

---

## Risk Register

| ID | Risk | Probability | Impact | Mitigation | Status |
|----|------|-------------|--------|------------|--------|
| R1 | QUIC client not implemented | 100% | **Blocker** | Implement in Rust first | ✅ Resolved |
| R2 | Stream I/O stubs | High | High | Implement in Phase 05 | ⚠️ Active |
| R3 | FFI bridge UB risk | High | Critical | Use `once_cell` | ✅ Resolved (Phase 04.1) |
| R4 | Camera permission denied | Medium | Medium | Fallback to manual entry | Planned |
| R5 | Secure storage fails | Low | Medium | Fallback to shared_prefs | Planned |
| R6 | xterm_flutter performance | Medium | High | Test with large output | Planned |
| R7 | First-connection MitM | Low | High | Document in security guide | Accepted |
| R8 | Certificate expiration | Low | Medium | User warning, re-pairing | Planned |

---

## Success Metrics

### Technical Metrics
- **Connection Latency**: <100ms (local network)
- **Terminal Throughput**: >1 MB/s
- **Memory Usage**: <100 MB (mobile app)
- **Battery Impact**: <5%/hour (active session)
- **Crash Rate**: <0.1% (per session)

### User Experience Metrics
- **First Connection Time**: <30 seconds (unboxing to connected)
- **Reconnection Time**: <5 seconds (auto-reconnect)
- **Terminal Responsiveness**: <50ms (input to output)
- **Setup Steps**: ≤3 steps (QR scan → Connected)

### Business Metrics (Post-Launch)
- **DAU/MAU Ratio**: >40% (daily active users)
- **Session Duration**: >20 minutes (average)
- **Retention (D7)**: >60% (7-day retention)
- **App Store Rating**: >4.5 stars

---

## Compliance & Standards

### Accessibility (WCAG 2.1 AA)
- ✅ Text contrast ratio ≥4.5:1
- ✅ Touch targets ≥48x48px
- ✅ Screen reader support (iOS VoiceOver, Android TalkBack)
- ✅ Keyboard navigation (external keyboard support)
- ✅ Color independence (status conveyed via icon + label)

### Security Standards
- ✅ OWASP Top 10 (2021) compliance
- ✅ TLS 1.3 with forward secrecy
- ✅ Certificate pinning (TOFU)
- ✅ Secure storage (Keychain/Keystore)
- ✅ No hardcoded secrets

### Platform Guidelines
- ✅ iOS Human Interface Guidelines
- ✅ Android Material Design 3
- ✅ App Store Review Guidelines
- ✅ Google Play Console Policies

---

## Open Questions

1. **Stream I/O Implementation**
   - Q: Should stream I/O be implemented in Phase 04 or Phase 05?
   - A: Phase 04 plan requires StreamSink, currently stubs
   - **Decision Required**: Before Flutter integration

2. **FFI Bridge Architecture**
   - Q: Should we use `once_cell` or `tokio::sync::RwLock` for static client?
   - A: `once_cell` recommended (simpler, thread-safe)
   - **Action**: Fix before production

3. **Certificate Rotation**
   - Q: How to handle certificate expiration/rotation?
   - A: Not in scope for MVP
   - **Future**: Phase 07 or later

4. **Multiple Concurrent Connections**
   - Q: Should app support multiple simultaneous hosts?
   - A: Not in scope for MVP
   - **Future**: User feedback priority

5. **Offline Mode**
   - Q: Should app support offline mode (command queuing)?
   - A: Not in scope for MVP
   - **Future**: User feedback priority

---

## References

### Internal Documentation
- [Codebase Summary](./codebase-summary.md)
- [Code Standards](./code-standards.md)
- [Design Guidelines](./design-guidelines.md)
- [System Architecture](./system-architecture.md)
- [Phase 04 Plan](../plans/260106-2127-comacode-mvp/phase-04-mobile-app.md)
- [Code Review Report](../plans/reports/code-reviewer-260107-1605-quic-client-phase04.md)

### External Resources
- [Quinn Documentation](https://docs.rs/quinn/0.11.0/quinn/)
- [Rustls 0.23 Migration](https://github.com/rustls/rustls/releases/tag/v0.23.0)
- [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/)
- [xterm.dart](https://pub.dev/packages/xterm_flutter)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

**Last Updated**: 2026-01-22
**Current Phase**: Phase VFS-2 - Virtual File System (File Watcher) - Flutter UI Complete
**Next Milestone**: Phase VFS-3 - File Operations (Read/Download)
**Maintainer**: Comacode Development Team
