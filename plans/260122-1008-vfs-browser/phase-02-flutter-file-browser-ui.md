# Phase 2: Flutter File Browser UI

## Overview

Create Flutter UI for browsing remote file system with directory navigation and chunk loading.

## Priority

P1 (High) - User-facing component for VFS feature

## Current Status

Pending

## Key Insights

- App uses Riverpod for state management
- Existing `ConnectionModel` and `BridgeWrapper` patterns
- Background receive task pattern from `quic_client.rs` can be leveraged
- Catppuccin Mocha theme for consistent styling

## Requirements

### Functional
- Display directory entries in list/tree view
- Navigate to parent directory
- Navigate into child directories
- Show file icons (folder vs file)
- Lazy loading with chunked data

### Non-Functional
- Smooth scrolling with 1000+ entries
- No UI freezes during data loading
- Proper error states (permission denied, not found)

## Architecture

### State Management

```dart
// Riverpod provider for VFS state
final vfsProvider = StateNotifierProvider<VfsNotifier, VfsState>((ref) {
  return VfsNotifier(ref.read(bridgeWrapperProvider));
});

class VfsState {
  final String currentPath;
  final List<DirEntry> entries;
  final bool isLoading;
  final bool hasMore;
  final String? error;
}
```

### Data Flow

```
Flutter UI              VfsNotifier              BridgeWrapper
    |                        |                        |
    |-- loadDir(path) ---->|-- requestListDir() ---->|-- QUIC to server
    |                        |                        |
    |<-- update(state) -----|<-- receiveDirChunk() ---|
    |                        |                        |
    |-- render entries      |                        |
```

## Related Code Files

### To Modify

| File | Changes |
|------|---------|
| `mobile/lib/bridge/bridge_wrapper.dart` | Add VFS methods |
| `mobile/lib/features/connection/connection_providers.dart` | Add VFS provider (or create new) |
| `mobile/lib/features/terminal/terminal_page.dart` | Add file browser button (optional) |

### To Create

| File | Purpose |
|------|---------|
| `mobile/lib/models/dir_entry.dart` | DirEntry Dart model |
| `mobile/lib/features/vfs/vfs_notifier.dart` | State management |
| `mobile/lib/features/vfs/vfs_page.dart` | Directory browser UI |
| `mobile/lib/features/vfs/widgets/entry_tile.dart` | File/folder entry widget |

## Implementation Steps

### Step 1: Dart Models

Create `mobile/lib/models/dir_entry.dart`:
```dart
class DirEntry {
  final String name;
  final String path;
  final bool isDir;
  final bool isSymlink;
  final int? size;
  final int? modified;
  final String? permissions;

  DirEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isSymlink = false,
    this.size,
    this.modified,
    this.permissions,
  });

  factory DirEntry.fromDynamic(Map<String, dynamic> json) {
    // Parse from FRB
  }
}
```

### Step 2: Bridge Wrapper Methods

Add to `bridge_wrapper.dart`:
```dart
Future<List<DirEntry>> listDirectory(String path) async {
  // Request listing
  await RustLib.instance.api.mobile_bridge_api_request_list_dir(path: path);

  // Receive chunks until has_more == false
  final entries = <DirEntry>[];
  bool hasMore = true;

  while (hasMore) {
    final chunk = await RustLib.instance.api.mobile_bridge_api_receive_dir_chunk();
    // Parse chunk, accumulate entries
    hasMore = chunk.hasMore;
    entries.addAll(chunk.entries);
  }

  return entries;
}
```

### Step 3: VFS Notifier

Create `vfs_notifier.dart`:
```dart
class VfsNotifier extends StateNotifier<VfsState> {
  final BridgeWrapper _bridge;

  VfsNotifier(this._bridge) : super(VfsState.initial());

  Future<void> loadDirectory(String path) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final entries = await _bridge.listDirectory(path);
      state = VfsState(
        currentPath: path,
        entries: entries,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void navigateUp() {
    final current = state.currentPath;
    final parent = path.dirname(current);
    loadDirectory(parent);
  }

  void navigateDown(String childPath) {
    loadDirectory(childPath);
  }
}
```

### Step 4: UI Components

#### Entry Tile Widget
```dart
class EntryTile extends StatelessWidget {
  final DirEntry entry;
  final VoidCallback onTap;

  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        entry.isDir ? Icons.folder : Icons.insert_drive_file,
        color: entry.isDir ? CatppuccinMocha.yellow : CatppuccinMocha.blue,
      ),
      title: Text(entry.name),
      subtitle: entry.isDir ? null : Text(_formatSize(entry.size)),
      trailing: Icon(Icons.chevron_right, size: 16),
      onTap: onTap,
    );
  }
}
```

#### VFS Page
```dart
class VfsPage extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vfsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_basename(state.currentPath)),
        actions: [
          if (state.currentPath != '/')
            IconButton(
              icon: Icon(Icons.arrow_upward),
              onPressed: () => ref.read(vfsProvider.notifier).navigateUp(),
            ),
        ],
      ),
      body: _buildBody(state, ref),
    );
  }

  Widget _buildBody(VfsState state, WidgetRef ref) {
    if (state.isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(child: Text('Error: ${state.error}'));
    }

    return ListView.builder(
      itemCount: state.entries.length,
      itemBuilder: (context, index) {
        final entry = state.entries[index];
        return EntryTile(
          entry: entry,
          onTap: () {
            if (entry.isDir) {
              ref.read(vfsProvider.notifier).navigateDown(entry.path);
            }
          },
        );
      },
    );
  }
}
```

## Todo List

- [ ] Create DirEntry model
- [ ] Add listDirectory to BridgeWrapper
- [ ] Create VfsNotifier
- [ ] Create EntryTile widget
- [ ] Create VfsPage with navigation
- [ ] Add parent directory navigation
- [ ] Handle error states
- [ ] Add loading indicators
- [ ] Test with large directories

## Success Criteria

- Open VFS page shows root directory
- Tap folder → navigate in
- Tap up arrow → navigate to parent
- Show 1000+ entries smoothly
- Error states display correctly

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| UI freezes on large dirs | Use ListView.builder lazy loading |
| Memory issues with many entries | Stream chunks, don't keep all in memory |
| Navigation loops | Detect parent = current, disable up button |
| FFI bridge hangs | Use async/await, timeout on requests |

## Security Considerations

- Don't expose sensitive paths in UI
- Mask permission errors for non-sensitive files
- Consider hiding hidden files option (default: show all)

## Next Steps

Depends on: Phase 1 (API) completed

After this phase:
- Test full end-to-end flow
- Consider adding file operations (delete, rename)
- Phase 3: (Future) Add reactive file watching

## Unresolved Questions

1. Entry sort order? (Recommend: name ascending, folders first)
2. Show file sizes in human-readable format? (Recommend: Yes, KB/MB/GB)
3. Cache directory listings? (Recommend: No for MVP, maybe Phase 3)
4. Integration with terminal - new tab or modal? (Recommend: New page from terminal)
