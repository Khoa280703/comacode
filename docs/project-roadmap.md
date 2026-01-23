# Project Roadmap

**Project**: Comacode
**Last Updated**: 2026-01-23
**Current Phase**: Vibe-03 (Vibe Coding Client - Polish & Performance) Complete

---

## Overview

Comacode enables remote terminal access via QR code pairing using QUIC protocol.

**Goal**: Simple, secure way to access remote terminal from mobile device.

---

## Phase Status

| Phase | Name | Status | Completion |
|-------|------|--------|------------|
| 01 | PTY Integration | ✅ Done | 100% |
| 02 | Auth + Rate Limiting | ✅ Done | 100% |
| 03 | QUIC Server | ✅ Done | 100% |
| 04 | QUIC Client (Mobile) | ✅ Done | 100% |
| 04.1 | Critical Bugfixes | ✅ Done | 100% |
| 05 | Network Protocol | ✅ Done | 100% |
| VFS-1 | VFS - Directory Listing | ✅ Done | 100% |
| VFS-2 | VFS - File Watcher | ✅ Done | 100% |
| 06 | Flutter UI | ✅ Done | 100% |
| Vibe-01 | Vibe Coding Client - MVP | ✅ Done | 100% |
| Vibe-02 | Vibe Coding Client - Enhanced Features | ✅ Done | 100% |
| Vibe-03 | Vibe Coding Client - Polish & Performance | ✅ Done | 100% |
| VFS-3 | File Operations (Read) | ⏳ TODO | 0% |
| 07 | Discovery & Auth | ⏳ TODO | 0% |
| 08 | Production Hardening | ⏳ TODO | 0% |

---

## Completed Phases

### Phase 01: PTY Integration
- [x] PTY spawn with `ptybo`
- [x] I/O stream handling
- [x] Window size change support

**Deliverable**: `crates/hostagent/src/pty.rs`

---

### Phase 02: Auth + Rate Limiting
- [x] JWT-like token generation (HMAC-SHA256)
- [x] Token validation middleware
- [x] IP-based rate limiting (in-memory)
- [x] Auto-ban on threshold exceeded

**Deliverable**: `crates/hostagent/src/auth.rs`, `crates/hostagent/src/ratelimit.rs`

---

### Phase 03: QUIC Server
- [x] Quinn 0.11 server setup
- [x] Rustls 0.23 with self-signed certs
- [x] Connection management
- [x] Session isolation

**Deliverable**: `crates/hostagent/src/quic_server.rs`

---

### Phase 04: QUIC Client (Mobile)
- [x] Quinn 0.11 client in Rust
- [x] TOFU verification (fingerprint normalization)
- [x] FFI bridge for Flutter
- [x] QR payload parsing

**Deliverable**: `crates/mobile_bridge/src/quic_client.rs`, `crates/mobile_bridge/src/api.rs`

---

### Phase 04.1: Critical Bugfixes
- [x] Fix UB in `api.rs` (replace `static mut` with `once_cell::sync::OnceCell`)
- [x] Fix fingerprint leakage in logs
- [x] Zero unsafe blocks (was 6, now 0)

**Deliverable**: Commit `00b6288`

---

### Phase 05: Network Protocol ✅
- [x] Stream I/O implementation
- [x] Bidirectional messaging
- [x] Terminal event streaming
- [x] Error handling and recovery

**Deliverable**: Complete QUIC stream I/O

---

### Phase VFS-1: Virtual File System - Directory Listing ✅
- [x] VFS module implementation (vfs.rs)
- [x] Directory listing with async I/O
- [x] Chunked streaming (150 entries/chunk)
- [x] Path validation with symlink resolution
- [x] VFS message types and error handling
- [x] FFI API for Flutter

**Deliverable**: `crates/hostagent/src/vfs.rs`

---

### Phase VFS-2: Virtual File System - File Watcher ✅
- [x] File watcher implementation (notify 7.0)
- [x] Push events for file changes
- [x] Watcher lifecycle management
- [x] Event propagation to client
- [x] Empty directory handling (explicit empty chunk)

**Deliverable**: File watcher with push events

---

### Phase 06: Flutter UI ✅
- [x] Terminal UI with xterm_flutter
- [x] Virtual key bar (ESC, CTRL, TAB, Arrows)
- [x] VFS browser with navigation
- [x] QR scanner with auto-connect
- [x] Connection state management (Riverpod)
- [x] Web dashboard with QR display (axum 0.7)
- [x] Catppuccin Mocha theme
- [x] Screen wakelock toggle
- [x] Font size adjustment (11-16px)

**Deliverable**: Complete Flutter mobile app

---

### Phase Vibe-01: Vibe Coding Client - MVP ✅
- [x] Chat-style interface for Claude Code CLI
- [x] Output display with xterm_flutter integration
- [x] Input bar with command submission
- [x] Quick keys toolbar (common keys)
- [x] Session tab bar for multiple sessions
- [x] Raw/Parsed output mode toggle
- [x] Connection state integration

**Deliverable**: `mobile/lib/features/vibe/` core UI components

---

### Phase Vibe-02: Vibe Coding Client - Enhanced Features ✅
- [x] Enhanced output parsing with OutputBlock model
- [x] OutputParser with heuristic patterns (files, diffs, errors, questions, lists, plans, code blocks, tool use)
- [x] ParsedOutputView with rich rendering (collapsible blocks, syntax highlighting)
- [x] Output search functionality with SearchOverlay widget
- [x] Case-sensitive search toggle
- [x] Search navigation (previous/next matches)
- [x] Security fix: Path validation in QUIC server's ReadFile handler

**Files Created**:
- `mobile/lib/features/vibe/models/output_block.dart` - Output block types and model
- `mobile/lib/features/vibe/widgets/output_parser.dart` - Heuristic pattern parser
- `mobile/lib/features/vibe/widgets/parsed_output_view.dart` - Rich output rendering
- `mobile/lib/features/vibe/widgets/search_overlay.dart` - Search functionality

**Files Modified**:
- `mobile/lib/features/vibe/vibe_session_page.dart` - Added search button, stateful widget
- `crates/hostagent/src/quic_server.rs` - Added path validation for ReadFile security

**Deliverable**: Enhanced Vibe Coding Client with smart output parsing and search

---

### Phase Vibe-03: Vibe Coding Client - Polish & Performance ✅
- [x] Haptic Feedback Service (HapticService with light/medium/heavy/selection/success/warning/error)
- [x] Ambient Animations (ThinkingIndicator with pulse animation, FadeTransitionWrapper, ScalePressAnimation)
- [x] Performance Optimization (OutputBuffer with MAX_LINES=10000, automatic line dropping, memory tracking)
- [x] Error Recovery (VibeErrorDialog with categorized errors, ErrorBanner for inline display)
- [x] UI Polish (haptic feedback integration throughout, smooth transitions)

**Files Created**:
- `mobile/lib/features/vibe/services/haptic_service.dart` - Haptic feedback service with 8 feedback types
- `mobile/lib/features/vibe/widgets/thinking_indicator.dart` - Ambient animations (ThinkingIndicator, FadeTransitionWrapper, ScalePressAnimation)
- `mobile/lib/features/vibe/models/output_buffer.dart` - Bounded output buffer to prevent memory issues
- `mobile/lib/features/vibe/widgets/error_dialog.dart` - Error recovery UI (VibeErrorDialog, ErrorBanner, ErrorData)

**Files Modified**:
- `mobile/lib/features/vibe/vibe_session_providers.dart` - Integrated OutputBuffer for memory management
- `mobile/lib/features/vibe/widgets/quick_keys_toolbar.dart` - Added haptic feedback on key press
- `mobile/lib/features/vibe/widgets/input_bar.dart` - Added haptic feedback for send and file attachment

**Key Features**:
- **HapticService**: Provides 8 types of haptic feedback (light, medium, heavy, selection, success, warning, error, notification)
- **ThinkingIndicator**: Pulsing animation when Claude is thinking (no recent output but still connected)
- **OutputBuffer**: Limits buffer to 10,000 lines max, drops oldest lines when full, tracks memory usage
- **VibeErrorDialog**: Categorized error dialogs (connection, authentication, file, dictation, generic) with custom actions
- **ErrorBanner**: Inline error banner with retry/dismiss actions

**Performance Improvements**:
- OutputBuffer prevents unbounded memory growth with MAX_LINES=10000
- Automatic line dropping when buffer reaches capacity
- Memory usage tracking for monitoring
- Debounced search in overlay (existing feature)

**Deliverable**: Polished Vibe Coding Client with haptic feedback, ambient animations, performance optimizations, and error recovery

---

## Upcoming Phases

### Phase VFS-3: File Operations (Read/Download)

**Goal**: Implement file read and download operations

**Tasks**:
- [ ] File read API (read file contents)
- [ ] Chunked file download (stream large files)
- [ ] File metadata caching
- [ ] Progress reporting for downloads
- [ ] Error handling for read failures

**Estimate**: 8-12h

**Dependencies**: None (can start immediately)

---

### Phase VFS-4: File Operations (Write/Upload)

**Goal**: Implement file write and upload operations

**Tasks**:
- [ ] File write API (create/overwrite files)
- [ ] Chunked file upload (stream large files)
- [ ] Append mode support
- [ ] Progress reporting for uploads
- [ ] Error handling for write failures

**Estimate**: 8-12h

**Dependencies**: Phase VFS-3

---

### Phase 07: Discovery & Auth

**Goal**: mDNS service discovery for zero-config setup

**Tasks**:
- [ ] mDNS advertisement (host broadcasts availability)
- [ ] mDNS browsing (client discovers hosts)
- [ ] QR code pairing option (fallback)
- [ ] Credential storage (secure keystore)
- [ ] Connection history
- [ ] Bluetooth LE discovery (optional fallback)

**Estimate**: 6-8h

**Dependencies**: Phase 06 (Flutter UI - complete)

---

### Phase 08: Production Hardening

**Goal**: Prepare for public release

**Tasks**:
- [ ] IP ban persistence (JSON file)
- [ ] Integration tests (end-to-end)
- [ ] Constant-time fingerprint comparison
- [ ] Error message improvements
- [ ] Configurable timeout values
- [ ] Security audit

**Estimate**: 6-8h

**Dependencies**: Phase 07

---

## Technical Debt Tracker

See `plans/260106-2127-comacode-mvp/known-issues-technical-debt.md`

| Issue | Priority | Phase |
|-------|----------|-------|
| File read/download | P1 | Phase VFS-3 |
| File write/upload | P1 | Phase VFS-4 |
| Integration tests | P2 | Phase 08 |
| IP ban persistence | P2 | Phase 08 |
| Constant-time comparison | P3 | Phase 08 |
| Hardcoded timeout | P2 | Phase 08 |
| Generic error messages | P2 | Phase 08 |

---

## Timeline

```
2026-01-06  │ Phase 01-03: MVP Complete
2026-01-07  │ Phase 04: QUIC Client Complete
2026-01-07  │ Phase 04.1: Bugfixes Complete
2026-01-09  │ Phase 05: Network Protocol Complete
2026-01-12  │ Phase VFS-1: VFS Directory Listing Complete
2026-01-15  │ Phase VFS-2: VFS File Watcher Complete
2026-01-22  │ Phase 06: Flutter UI Complete
2026-01-23  │ Phase Vibe-01: Vibe Coding Client MVP Complete
2026-01-23  │ Phase Vibe-02: Vibe Enhanced Features Complete
2026-01-23  │ Phase Vibe-03: Vibe Polish & Performance Complete
────────────┼───────────────────────────────────
TBD         │ Phase VFS-3: File Operations Read (8-12h)
TBD         │ Phase VFS-4: File Operations Write (8-12h)
TBD         │ Phase 07: Discovery & Auth (6-8h)
TBD         │ Phase 08: Production Hardening (6-8h)
```

---

## Success Criteria

- [x] Mobile app can connect to hostagent via QR scan
- [x] Terminal I/O works bidirectionally
- [x] TOFU verification prevents MitM
- [x] Rate limiting protects against abuse
- [x] VFS directory listing works
- [x] File watcher with push events
- [x] Flutter UI complete (terminal, VFS, QR scanner)
- [ ] mDNS discovery works (Phase 07)
- [ ] File read/download (Phase VFS-3)
- [ ] File write/upload (Phase VFS-4)
- [ ] Production-ready (hardened, tested)
