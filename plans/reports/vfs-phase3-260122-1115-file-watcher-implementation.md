# VFS Browser Phase 3: File Watcher - Implementation Report

**Date:** 2026-01-22
**Status:** Backend Complete, Dart Bindings Blocked
**Phase:** VFS-3 - Real-time File System Sync

## Summary

Implemented file system watcher backend using `notify` v7.0 crate. Server watches directories and pushes `FileEvent` messages to clients via QUIC. Mobile client FFI layer ready but Dart bindings blocked by FRB config issues.

## Completed Work

### Backend (Rust)

1. **Core Types** (`crates/core/src/types/message.rs`)
   - `FileEventType` enum: `Created`, `Modified`, `Deleted`, `Renamed { old_name }`
   - `NetworkMessage` variants:
     - `WatchDir { path }`
     - `WatchStarted { watcher_id }`
     - `FileEvent { watcher_id, path, event_type, timestamp }`
     - `UnwatchDir { watcher_id }`
     - `WatchError { watcher_id, error }`

2. **File Watcher Module** (`crates/hostagent/src/vfs_watcher.rs`)
   - `WatcherManager` - manages active directory watchers
   - `CallbackHandler` - implements `notify::EventHandler`
   - `WatchEvent` struct for callbacks
   - Uses `notify::recommended_watcher` with `EventHandler` trait (v7 API)

3. **QUIC Server** (`crates/hostagent/src/quic_server.rs`)
   - Added `watcher_mgr: Arc<WatcherManager>` to `QuicServer`
   - `WatchDir` handler - validates path, starts watcher, sends `WatchStarted`
   - `UnwatchDir` handler - stops watcher
   - Events pushed to client via `send_message()`

4. **Mobile Client** (`crates/mobile_bridge/src/quic_client.rs`)
   - `file_event_buffer: Arc<Mutex<Vec<NetworkMessage>>>` (cap: 1000 events)
   - `request_watch_dir(path)` - sends WatchDir message
   - `request_unwatch_dir(watcher_id)` - sends UnwatchDir message
   - `receive_file_event()` - polls buffer (non-blocking)
   - Event structs: `FileWatcherEvent`, `WatcherStartedEvent`, `WatcherErrorEvent`

5. **FFI Layer** (`crates/mobile_bridge/src/api.rs`)
   - `request_watch_dir(path: String)` - async FFI function
   - `request_unwatch_dir(watcher_id: String)` - async FFI function
   - `receive_file_event()` - returns `Option<FileWatcherEventData>`
   - `file_event_buffer_len()` - monitoring

### Build Status

| Crate | Status | Notes |
|-------|--------|-------|
| comacode-core | ✅ PASS | FileEventType exported |
| hostagent | ✅ PASS | notify v7, EventHandler working |
| mobile_bridge | ⚠️ PARTIAL | Rust code OK, FRB generated code has conflicts |

## Blocked Work

### Dart Bindings (FRB)

**Issue:** `flutter_rust_bridge_codegen` generates code with type resolution conflicts.

**Errors:**
- `use mobile_bridge::api::*` in generated code should be `use crate::api::*`
- Duplicate type definitions (DirEntry, TerminalCommand) between generated and existing code
- FileWatcherEventData not accessible from quic_client module

**Attempted Fixes:**
1. Changed config `rust_input: mobile_bridge::api` → `crate::api`
2. Manual patch of generated code (mobile_bridge → crate)
3. Exported types from api.rs module

**Root Cause:** FRB config expects crate-style paths but generates wrong module references when used from outside lib.rs context.

## Files Modified

```
crates/
├── core/src/types/
│   ├── message.rs     # + FileEventType enum, watcher messages
│   └── mod.rs          # + export FileEventType
├── hostagent/
│   ├── Cargo.toml      # + notify = "7.0"
│   ├── src/
│   │   ├── main.rs      # + mod vfs_watcher
│   │   ├── vfs_watcher.rs   # NEW (WatcherManager)
│   │   └── quic_server.rs    # + WatchDir/UnwatchDir handlers
└── mobile_bridge/src/
    ├── quic_client.rs  # + file_event_buffer, watcher methods
    └── api.rs          # + FFI functions for Dart
```

## Next Steps

### Option A: Fix FRB Bindings (Recommended for MVP)
1. Research `flutter_rust_bridge` v2.11 config for non-lib modules
2. Or move all FFI types to separate `ffi_types.rs` module
3. Or use explicit `#[frb]` attributes on each type

### Option B: Manual Dart Bindings (Quick Workaround)
1. Skip FRB for FileWatcherEventData
2. Write manual Dart bridge using `dart:ffi`
3. Less elegant but gives full control

### Option C: Test Backend First (Conservative)
1. Run hostagent, test watcher with CLI client
2. Verify FileEvent messages flow correctly
3. Return to Dart bindings after backend validation

## Testing Checklist

- [ ] Start hostagent with watcher enabled
- [ ] Connect and send `WatchDir` message
- [ ] Create/modify/delete file in watched directory
- [ ] Verify `FileEvent` received on client side
- [ ] Test `UnwatchDir` stops watching
- [ ] Test multiple watchers (limit: 1 per session)

## Questions

1. **FRB Config:** Should types be in separate module to avoid conflicts?
2. **Watcher Limits:** Should we enforce max 1 watcher per session for MVP?
3. **Path Validation:** Current check allows only session_dir. Expand or keep strict?

## Code Quality

- **Warnings:** 1 unused warning in hostagent (dead_code)
- **Tests:** Basic unit test added (`test_watcher_manager_new`)
- **Docs:** Module-level docs added, inline comments for complex logic
- **Safety:** Buffer caps (1000 file events) prevent OOM
