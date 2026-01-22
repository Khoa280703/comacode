# Phase 1: Directory Listing API

## Overview

Add protocol messages and server-side logic for directory listing with chunking support.

## Priority

P1 (High) - Core functionality for VFS feature

## Current Status

**DONE (2026-01-22)** - Phase 1 completed successfully

## Key Insights

From codebase exploration:
- Protocol uses Postcard serialization with length-prefixed format
- Existing `OutputStream` pattern for snapshot could be adapted
- Background receive task in `quic_client.rs` can handle `DirChunk` messages
- No existing file system operations in business logic

## Requirements

### Functional
- Client requests directory listing with path
- Server returns entries in chunks (100-200 items)
- Support pagination for large directories
- Handle errors (not found, permission denied)

### Non-Functional
- 1000 files listed in < 1 second
- Minimal memory overhead (stream chunks, not all in memory)
- Graceful error handling

## Architecture

### Message Flow

```
Client                          Server
  |                               |
  |------- ListDir {path} ----->|
  |                               |  <- Read directory
  |                               |  <- Split into chunks
  |<---- DirChunk {chunk:0} ----|
  |<---- DirChunk {chunk:1} ----|
  |                               |
  |------- ListDir {path2} ----->|
  |                               |
```

### Data Structures

```rust
// In crates/core/src/types/message.rs
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: Option<u64>,
    pub modified: Option<u64>,
    pub permissions: Option<String>,
}

NetworkMessage::ListDir {
    path: String,
    depth: Option<u32>,  // Reserved for future
}

NetworkMessage::DirChunk {
    chunk_index: u32,
    total_chunks: u32,
    entries: Vec<DirEntry>,
    has_more: bool,
}
```

## Related Code Files

### To Modify

| File | Changes |
|------|---------|
| `crates/core/src/types/message.rs` | Add `ListDir`, `DirChunk`, `DirEntry` |
| `crates/core/src/types/mod.rs` | Export new types |
| `crates/core/src/error.rs` | Add `FileNotFound`, `PermissionDenied`, `NotADirectory` |
| `crates/hostagent/src/quic_server.rs` | Handle `ListDir` in message loop |
| `crates/hostagent/src/vfs.rs` | **CREATE** - File system operations |
| `crates/mobile_bridge/src/api.rs` | Add `request_list_dir()`, `receive_dir_chunk()` FFI |
| `crates/mobile_bridge/src/quic_client.rs` | Add `dir_chunk_buffer`, update receive loop |

### To Create

| File | Purpose |
|------|---------|
| `crates/hostagent/src/vfs.rs` | Directory reading logic, error handling |

## Implementation Steps

### Step 1: Core Types (crates/core)

1. Add `DirEntry` struct to `types/message.rs`
2. Add `ListDir { path: String, depth: Option<u32> }` variant
3. Add `DirChunk { chunk_index, total_chunks, entries, has_more }` variant
4. Add error types to `error.rs`

### Step 2: Server VFS Module (crates/hostagent)

Create `vfs.rs`:
```rust
use std::path::Path;
use tokio::fs;

pub async fn read_directory(path: &Path) -> Result<Vec<DirEntry>, VfsError> {
    let mut entries = Vec::new();
    let mut dir = fs::read_dir(path)
        .await
        .map_err(|e| VfsError::IoError(e.to_string()))?;

    while let Some(entry) = dir.next_entry().await
        .map_err(|e| VfsError::IoError(e.to_string()))?
    {
        let metadata = entry.metadata().await
            .map_err(|e| VfsError::IoError(e.to_string()))?;

        entries.push(DirEntry {
            name: entry.file_name().to_string_lossy().to_string(),
            path: entry.path().to_string_lossy().to_string(),
            is_dir: metadata.is_dir(),
            is_symlink: metadata.is_symlink(),
            size: Some(metadata.len()),
            modified: Some(metadata.modified()?.duration_since(UNIX_EPOCH)?.as_secs() as u64),
            permissions: None, // TODO: mode permissions
        });
    }

    Ok(entries)
}

pub fn chunk_entries(entries: Vec<DirEntry>, chunk_size: usize) -> Vec<Vec<DirEntry>> {
    entries.chunks(chunk_size).map(|c| c.to_vec()).collect()
}
```

### Step 3: Server Message Handler (quic_server.rs)

Add to `handle_stream()` or main message loop:
```rust
NetworkMessage::ListDir { path, depth: _ } => {
    let path = PathBuf::from(path);

    // Validate path
    if !path.exists() {
        let error = NetworkMessage::Error {
            code: 404,
            message: "Path not found".to_string(),
        };
        Self::send_message(&mut send, &error).await?;
        break;
    }

    // Read directory
    let entries = vfs::read_directory(&path).await?;

    // Chunk into batches of 150
    let chunks = vfs::chunk_entries(entries, 150);
    let total = chunks.len() as u32;

    for (i, chunk) in chunks.iter().enumerate() {
        let msg = NetworkMessage::DirChunk {
            chunk_index: i as u32,
            total_chunks: total,
            entries: chunk.clone(),
            has_more: i < chunks.len() - 1,
        };
        Self::send_message(&mut send, &msg).await?;
    }
}
```

### Step 4: Client Buffer (quic_client.rs)

Add to `QuicClient` struct:
```rust
dir_chunk_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
```

Update receive loop to push `DirChunk` messages to buffer.

Add method:
```rust
pub async fn receive_dir_chunk(&self) -> Result<Option<NetworkMessage>, String> {
    let mut buffer = self.dir_chunk_buffer.lock().await;

    // Filter only DirChunk messages
    let chunks: Vec<_> = buffer.drain(..)
        .filter(|m| matches!(m, NetworkMessage::DirChunk { .. }))
        .collect();

    if chunks.is_empty() {
        Ok(None)
    } else {
        Ok(Some(chunks.swap_remove(0)))
    }
}
```

### Step 5: FFI Bridge (api.rs)

```rust
#[frb(sync)]
pub fn mobile_bridge_api_request_list_dir(
    path: String,
) -> Result<(), String> {
    // Send ListDir message via QUIC
}

#[frb(sync)]
pub fn mobile_bridge_api_receive_dir_chunk(
) -> Result<DirChunk, String> {
    // Poll from dir_chunk_buffer
}
```

## Todo List

- [x] Add DirEntry, ListDir, DirChunk to core types
- [x] Add VFS error types
- [x] Create vfs.rs module with read_directory()
- [x] Add ListDir handler in quic_server.rs
- [x] Add dir_chunk_buffer to quic_client.rs
- [x] Update receive loop to handle DirChunk
- [x] Add FFI functions in api.rs
- [x] Generate Dart bindings
- [x] Test with large directory (1000+ files)

## Success Criteria

- Request `/tmp` returns entries
- Large directory (1000 files) returns in chunks
- Non-existent path returns error
- Permission denied handled gracefully
- No memory leaks in chunking

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Path traversal attacks | Validate paths, chroot to working dir |
| Symbolic link loops | Don't follow symlinks in MVP |
| Large directories | Chunk size limit (150 entries) |
| Memory exhaustion | Stream chunks, don't buffer all |

## Security Considerations

- Validate all paths against directory traversal (`../`)
- Limit recursion depth (ignore `depth` in MVP)
- Don't expose full filesystem in production
- Consider adding allowlist of accessible paths

## Next Steps

Depends on: Protocol types added to core

After this phase:
- Phase 2: Flutter UI implementation
- Phase 3: (Future) Add file watching

## Unresolved Questions

1. Should we follow symlinks? (Decision: No for MVP)
2. Path sandboxing needed? (Decision: Yes, chroot to session home)
3. Include hidden files (starting with `.`)? (Decision: Yes, show all)
