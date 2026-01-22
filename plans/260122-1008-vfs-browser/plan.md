---
title: "Virtual File System Browser - 3 Phase Implementation"
description: "Add directory browsing to mobile terminal with request-response chunking (Phase 1), Flutter UI (Phase 2), and real-time file watching (Phase 3)"
status: in-progress
priority: P2
effort: 18h
tags: [feature, vfs, mobile, rust, flutter]
created: 2026-01-22
---

# Virtual File System Browser - Implementation Plan

## Overview

Add directory browser functionality to Comacode mobile terminal app, allowing users to browse remote file system structure with real-time sync. Implementation split into 3 phases to prioritize MVP delivery.

## Phases

| # | Phase | Status | Effort | Link |
|---|-------|--------|--------|------|
| 1 | Directory Listing API | **DONE (2026-01-22)** | 6h | [phase-01](./phase-01-directory-listing-api.md) |
| 2 | Flutter File Browser UI | Pending | 4h | [phase-02](./phase-02-flutter-file-browser-ui.md) |
| 3 | Real-time File Watching | Pending | 8h | [phase-03](./phase-03-file-watcher.md) |

## Dependencies

- Current terminal streaming must work reliably
- Postcard serialization (already in use)
- Existing QUIC stream infrastructure
- Flutter Rust Bridge v2.11+

## Key Decisions

### Phase 1: Request-Response + Chunking
- **Protocol**: Add `ListDir` / `DirChunk` messages
- **Serialization**: Use existing Postcard format
- **Chunking**: 100-200 entries per chunk
- **Pattern**: Request-response with async polling

### Phase 2: Flutter UI
- Riverpod state management
- Directory navigation (parent/child)
- Lazy loading with ListView.builder

### Phase 3: Real-time File Watching
- `notify` crate for cross-platform file watching
- Server push events on file changes
- Auto-refresh directory listing
- Battery-efficient (watch only active directory)

## Related Code Files

### To Modify
- `crates/core/src/types/message.rs` - Add VFS message types
- `crates/core/src/error.rs` - Add VFS error types
- `crates/hostagent/src/quic_server.rs` - Handle ListDir messages
- `crates/mobile_bridge/src/api.rs` - Add FFI functions
- `crates/mobile_bridge/src/quic_client.rs` - Handle DirChunk in receive loop

### To Create
- `crates/hostagent/src/vfs.rs` - File system operations module
- `crates/hostagent/src/vfs_watcher.rs` - File watching logic
- `mobile/lib/features/vfs/` - Directory browser UI
- `mobile/lib/models/dir_entry.dart` - DirEntry model
- `mobile/lib/features/vfs/vfs_watcher_notifier.dart` - Watch state management

## Success Criteria

- Phase 1: List directory with 1000 files < 1s
- Phase 1: Navigate parent/child directories
- Phase 1: Handle permission errors gracefully
- Phase 2: Smooth UI with 1000+ entries
- Phase 3: File changes via terminal appear in VFS within 2s
- Phase 3: Minimal battery impact (watch only active dir)
