# Phase 3: File Watcher - Real-time Sync

## Overview

Add real-time file system monitoring with server push events to sync changes when files are modified via terminal or external processes.

## Priority

P2 (Medium) - Nice-to-have feature for enhanced UX

## Current Status

Pending

## Key Insights

- Rust `notify` crate (v6+) provides cross-platform file watching
- Server already has background receive task pattern
- Flutter needs reactive state update on file events
- Mobile battery constraints → watch only active directory

## Requirements

### Functional

- Watch current directory for changes
- Notify client on: create, modify, delete, rename
- Auto-refresh directory listing on change
- Unwatch when navigating away

### Non-Functional

- Minimal battery impact (debounce, coalesce)
- Handle watch failures gracefully
- Re-watch on server reconnect

## Architecture

### Message Flow

```
Client                          Server
  |                               |
  |------- WatchDir {path} ------>|
  |                               |  <- spawn notify watcher
  |<------- WatchStarted ---------|
  |                               |
  |                          (file change detected)
  |<------ FileEvent {event} -----|
  |                               |
  |<- refresh directory listing ->|
  |                               |
  |------- UnwatchDir ------------>|
  |                               |  <- cancel watcher
```

### Data Structures

```rust
// In crates/core/src/types/message.rs

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FileEventType {
    Created,
    Modified,
    Deleted,
    Renamed { old_name: String },
}

NetworkMessage::WatchDir {
    path: String,
    // Optional: filter patterns
    include_patterns: Vec<String>,
    exclude_patterns: Vec<String>,
}

NetworkMessage::WatchStarted {
    watcher_id: String,
}

NetworkMessage::FileEvent {
    watcher_id: String,
    path: String,
    event_type: FileEventType,
    timestamp: u64,
}

NetworkMessage::UnwatchDir {
    watcher_id: String,
}

NetworkMessage::WatchError {
    watcher_id: String,
    error: String,
}
```

## Related Code Files

### To Modify

| File | Changes |
|------|---------|
| `crates/core/src/types/message.rs` | Add WatchDir, FileEvent, etc. |
| `crates/hostagent/src/quic_server.rs` | Handle watch messages |
| `crates/hostagent/src/vfs.rs` | Add watcher module |
| `crates/hostagent/Cargo.toml` | Add `notify` dependency |
| `crates/mobile_bridge/src/api.rs` | Add watch FFI functions |
| `crates/mobile_bridge/src/quic_client.rs` | Handle FileEvent in receive loop |

### To Create

| File | Purpose |
|------|---------|
| `crates/hostagent/src/vfs_watcher.rs` | File watching logic |
| `mobile/lib/features/vfs/vfs_watcher_notifier.dart` | Watch state management |

## Implementation Steps

### Step 1: Add Dependency

**File:** `crates/hostagent/Cargo.toml`

```toml
[dependencies]
# File watching (Phase 3)
notify = "6.1"
```

### Step 2: Core Types

**File:** `crates/core/src/types/message.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FileEventType {
    Created,
    Modified,
    Deleted,
    Renamed { old_name: String },
}

// Add to NetworkMessage enum:
WatchDir {
    path: String,
    include_patterns: Vec<String>,  // glob patterns
    exclude_patterns: Vec<String>,  // glob patterns
},
WatchStarted {
    watcher_id: String,
},
FileEvent {
    watcher_id: String,
    path: String,
    event_type: FileEventType,
    timestamp: u64,
},
UnwatchDir {
    watcher_id: String,
},
WatchError {
    watcher_id: String,
    error: String,
},
```

### Step 3: Server Watcher Module

**File:** `crates/hostagent/src/vfs_watcher.rs`

```rust
use notify::{EventKind, RecursiveMode, Watcher, recommended_watcher};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;
use std::collections::HashMap;
use anyhow::Result;

pub struct WatcherManager {
    watchers: Arc<Mutex<HashMap<String, notify::RecommendedWatcher>>>,
}

impl WatcherManager {
    pub fn new() -> Self {
        Self {
            watchers: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn watch_directory(
        &self,
        watcher_id: String,
        path: &Path,
        mut on_event: impl FnMut(FileEvent) + Send + 'static,
    ) -> Result<()> {
        let path = path.to_path_buf();

        // Create debounced watcher (2 seconds coalesce)
        let mut watcher = recommended_watcher(move |res: notify::Result<notify::Event>| {
            if let Ok(event) = res {
                self.process_event(&event, &mut on_event);
            }
        })?;

        watcher.watch(&path, RecursiveMode::NonRecursive)?;

        self.watchers.lock().await.insert(watcher_id.clone(), watcher);

        Ok(())
    }

    pub async fn unwatch(&self, watcher_id: &str) -> Result<()> {
        let mut watchers = self.watchers.lock().await;
        if let Some(watcher) = watchers.remove(watcher_id) {
            // Watcher dropped on removal
        }
        Ok(())
    }

    fn process_event(&self, event: &notify::Event, on_event: &mut impl FnMut(FileEvent)) {
        use notify::EventKind::*;

        let event_type = match event.kind {
            Create(_) => FileEventType::Created,
            Modify(_) => FileEventType::Modified,
            Remove(_) => FileEventType::Deleted,
            Rename(_) => {
                // Extract old name from event
                FileEventType::Renamed {
                    old_name: extract_old_name(event),
                }
            }
            _ => return, // Ignore other events
        };

        for path in event.paths.iter() {
            on_event(FileEvent {
                watcher_id: self.id.clone(),
                path: path.to_string_lossy().to_string(),
                event_type: event_type.clone(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
            });
        }
    }
}

pub struct FileEvent {
    pub watcher_id: String,
    pub path: String,
    pub event_type: FileEventType,
    pub timestamp: u64,
}
```

### Step 4: Server Message Handler

**File:** `crates/hostagent/src/quic_server.rs`

```rust
use crate::vfs_watcher::WatcherManager;

// Add to session state
struct VfsSession {
    watcher_mgr: Arc<WatcherManager>,
    active_watchers: HashMap<String, String>, // watcher_id -> path
}

// In message handler:
NetworkMessage::WatchDir { path, include_patterns, exclude_patterns } => {
    // Validate path exists
    let path_buf = PathBuf::from(&path);
    if !path_buf.exists() {
        send_error(&mut send, 404, "Path not found").await?;
        break;
    }

    let watcher_id = format!("watch_{}", session_id);
    let send_clone = send_shared.clone();

    vfs_session.watcher_mgr.watch_directory(
        watcher_id.clone(),
        &path_buf,
        move |event| {
            let msg = NetworkMessage::FileEvent {
                watcher_id: event.watcher_id,
                path: event.path,
                event_type: event.event_type,
                timestamp: event.timestamp,
            };

            // Send to client (spawn to avoid blocking watcher)
            let mut send = send_clone.clone();
            tokio::spawn(async move {
                let _ = Self::send_message(&mut send.lock().await, &msg).await;
            });
        },
    ).await?;

    vfs_session.active_watchers.insert(watcher_id.clone(), path);

    Self::send_message(&mut send, &NetworkMessage::WatchStarted {
        watcher_id,
    }).await?;
}

NetworkMessage::UnwatchDir { watcher_id } => {
    vfs_session.watcher_mgr.unwatch(&watcher_id).await?;
    vfs_session.active_watchers.remove(&watcher_id);
}

NetworkMessage::FileEvent { watcher_id, path, event_type, timestamp } => {
    // Forward to client's event buffer (similar to TerminalEvent)
    // Add to file_event_buffer in quic_client.rs
}
```

### Step 5: Client Buffer

**File:** `crates/mobile_bridge/src/quic_client.rs`

```rust
pub struct QuicClient {
    // ... existing fields
    file_event_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
}

// Update receive loop:
match msg {
    NetworkMessage::FileEvent { .. } => {
        self.file_event_buffer.lock().await.push(msg);
    }
    // ... other cases
}

pub async fn receive_file_event(&self) -> Result<Option<NetworkMessage>, String> {
    let mut buffer = self.file_event_buffer.lock().await;

    let events: Vec<_> = buffer.drain(..)
        .filter(|m| matches!(m, NetworkMessage::FileEvent { .. }))
        .collect();

    if events.is_empty() {
        Ok(None)
    } else {
        Ok(Some(events.swap_remove(0)))
    }
}
```

### Step 6: FFI Bridge

**File:** `crates/mobile_bridge/src/api.rs`

```rust
#[frb(sync)]
pub fn mobile_bridge_api_request_watch_dir(
    path: String,
) -> Result<String, String> {
    // Send WatchDir message, return watcher_id
}

#[frb(sync)]
pub fn mobile_bridge_api_receive_file_event(
) -> Result<FileEvent, String> {
    // Poll from file_event_buffer
}

#[frb(sync)]
pub fn mobile_bridge_api_unwatch_dir(
    watcher_id: String,
) -> Result<(), String> {
    // Send UnwatchDir message
}
```

### Step 7: Flutter Watcher Notifier

**File:** `mobile/lib/features/vfs/vfs_watcher_notifier.dart`

```dart
class FileEvent {
  final String watcherId;
  final String path;
  final String eventType;  // "created", "modified", "deleted", "renamed"
  final int timestamp;

  FileEvent({
    required this.watcherId,
    required this.path,
    required this.eventType,
    required this.timestamp,
  });
}

class VfsWatcherNotifier extends StateNotifier<WatcherState> {
  final BridgeWrapper _bridge;
  Timer? _pollTimer;

  VfsWatcherNotifier(this._bridge) : super(WatcherState.initial());

  Future<void> watchDirectory(String path) async {
    try {
      final watcherId = await _bridge.requestWatchDir(path);
      state = state.copyWith(
        isWatching: true,
        currentWatcherId: watcherId,
      );
      _startPolling();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      final event = await _bridge.receiveFileEvent();
      if (event != null) {
        state = state.copyWith(lastEvent: event);
        // Notify VFS to refresh
      }
    });
  }

  Future<void> unwatch() async {
    _pollTimer?.cancel();
    if (state.currentWatcherId != null) {
      await _bridge.unwatchDir(state.currentWatcherId!);
    }
    state = WatcherState.initial();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

class WatcherState {
  final bool isWatching;
  final String? currentWatcherId;
  final FileEvent? lastEvent;
  final String? error;

  WatcherState({
    required this.isWatching,
    this.currentWatcherId,
    this.lastEvent,
    this.error,
  });

  factory WatcherState.initial() => WatcherState(isWatching: false);

  WatcherState copyWith({
    bool? isWatching,
    String? currentWatcherId,
    FileEvent? lastEvent,
    String? error,
  }) {
    return WatcherState(
      isWatching: isWatching ?? this.isWatching,
      currentWatcherId: currentWatcherId ?? this.currentWatcherId,
      lastEvent: lastEvent ?? this.lastEvent,
      error: error ?? this.error,
    );
  }
}
```

### Step 8: Integrate with VfsPage

**File:** `mobile/lib/features/vfs/vfs_page.dart`

```dart
class VfsPage extends ConsumerStatefulWidget {
  @override
  ConsumerState<VfsPage> createState() => _VfsPageState();
}

class _VfsPageState extends ConsumerState<VfsPage> {
  @override
  void initState() {
    super.initState();
    // Start watching when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(vfsProvider);
      ref.read(vfsWatcherProvider.notifier).watchDirectory(state.currentPath);
    });
  }

  @override
  void dispose() {
    // Stop watching when leaving
    ref.read(vfsWatcherProvider.notifier).unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vfsProvider);
    final watcherState = ref.watch(vfsWatcherProvider);

    // Auto-refresh on file event
    ref.listen(vfsWatcherProvider, (previous, next) {
      if (next.lastEvent != null && previous?.lastEvent != next.lastEvent) {
        ref.read(vfsProvider.notifier).loadDirectory(state.currentPath);
      }
    });

    return Scaffold(
      // ... existing UI
    );
  }
}
```

## Todo List

- [ ] Add notify dependency to hostagent
- [ ] Add FileEvent types to core messages
- [ ] Create vfs_watcher.rs module
- [ ] Add WatchDir handler in quic_server.rs
- [ ] Add file_event_buffer to quic_client.rs
- [ ] Add watch FFI functions in api.rs
- [ ] Generate Dart bindings
- [ ] Create VfsWatcherNotifier
- [ ] Integrate watcher with VfsPage
- [ ] Test file creation via terminal
- [ ] Test file deletion via terminal
- [ ] Test battery impact

## Success Criteria

- Create file via terminal → appears in VFS within 2s
- Delete file via terminal → removed from VFS
- Navigate away → watcher stops (battery save)
- Navigate back → watcher resumes

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| High battery drain | Watch only active dir, debounced events |
| Too many events | Coalesce 2s window, limit rate |
| Watcher fails on some paths | Graceful error, fallback to manual refresh |
| Missing events (race condition) | Full refresh on any event |

## Security Considerations

- Don't watch paths outside session home
- Limit total watchers per session
- Sanitize error messages (don't leak paths)

## Unresolved Questions

1. Should we watch recursively? (Recommend: No for MVP, NonRecursive mode)
2. Debounce duration? (Recommend: 2s default)
3. Max watchers per session? (Recommend: 1 active directory only)
4. Handle symbolic links? (Recommend: Don't follow symlinks in watcher)

## Dependencies

Depends on: Phase 1 (API) completed

After this phase:
- Consider Phase 4: File operations (upload/download)
- Phase 5: Advanced features (search, favorites)
