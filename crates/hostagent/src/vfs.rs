//! Virtual File System operations
//!
//! Provides directory reading, file listing, and path validation for VFS browsing.

use std::path::Path;
use tokio::fs;
use comacode_core::{types::DirEntry, CoreError};

/// VFS operation result
pub type VfsResult<T> = Result<T, VfsError>;

/// VFS-specific errors
#[derive(Debug)]
pub enum VfsError {
    IoError(String),
    PathNotFound(String),
    NotADirectory(String),
    PermissionDenied(String),
}

impl std::fmt::Display for VfsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VfsError::IoError(e) => write!(f, "I/O error: {}", e),
            VfsError::PathNotFound(p) => write!(f, "Path not found: {}", p),
            VfsError::NotADirectory(p) => write!(f, "Not a directory: {}", p),
            VfsError::PermissionDenied(p) => write!(f, "Permission denied: {}", p),
        }
    }
}

impl std::error::Error for VfsError {}

impl From<VfsError> for CoreError {
    fn from(err: VfsError) -> Self {
        match err {
            VfsError::PathNotFound(p) => CoreError::PathNotFound(p),
            VfsError::NotADirectory(p) => CoreError::NotADirectory(p),
            VfsError::PermissionDenied(p) => CoreError::PermissionDenied(p),
            VfsError::IoError(e) => CoreError::VfsIoError(e),
        }
    }
}

/// Read directory entries from given path
///
/// Returns sorted entries (directories first, then alphabetically by name).
/// Does NOT follow symlinks.
pub async fn read_directory(path: &Path) -> VfsResult<Vec<DirEntry>> {
    // Check if path exists
    if !path.exists() {
        return Err(VfsError::PathNotFound(path.display().to_string()));
    }

    // Check if path is a directory
    if !path.is_dir() {
        return Err(VfsError::NotADirectory(path.display().to_string()));
    }

    let mut entries = Vec::new();
    let mut dir = fs::read_dir(path)
        .await
        .map_err(|e| {
            // Permission denied -> specific error
            if e.kind() == std::io::ErrorKind::PermissionDenied {
                VfsError::PermissionDenied(path.display().to_string())
            } else {
                VfsError::IoError(e.to_string())
            }
        })?;

    while let Some(entry) = dir.next_entry().await
        .map_err(|e| VfsError::IoError(e.to_string()))?
    {
        let metadata = entry.metadata().await
            .map_err(|e| VfsError::IoError(e.to_string()))?;

        let modified = metadata.modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs());

        entries.push(DirEntry {
            name: entry.file_name().to_string_lossy().to_string(),
            path: entry.path().to_string_lossy().to_string(),
            is_dir: metadata.is_dir(),
            is_symlink: metadata.is_symlink(),
            size: Some(metadata.len()),
            modified,
            permissions: None, // Reserved for future
        });
    }

    // Sort: directories first, then by name
    entries.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.cmp(&b.name),
        }
    });

    Ok(entries)
}

/// Split entries into chunks for streaming
///
/// # Arguments
/// * `entries` - Full list of directory entries
/// * `chunk_size` - Target size per chunk (default: 150)
pub fn chunk_entries(entries: Vec<DirEntry>, chunk_size: usize) -> Vec<Vec<DirEntry>> {
    entries.chunks(chunk_size).map(|c: &[DirEntry]| c.to_vec()).collect()
}

/// Validate path for security
///
/// Uses canonicalize to resolve all symlinks and relative components.
/// Then checks if the resolved path is still within allowed bounds.
pub fn validate_path(path: &Path, allowed_base: &Path) -> VfsResult<()> {
    // Canonicalize resolves all "..", ".", symlinks
    let canonical = path.canonicalize()
        .map_err(|_| VfsError::PathNotFound(path.display().to_string()))?;

    let allowed_canonical = allowed_base.canonicalize()
        .unwrap_or_else(|_| allowed_base.to_path_buf());

    // Check if canonical path starts with allowed base
    if !canonical.starts_with(&allowed_canonical) {
        return Err(VfsError::PermissionDenied(
            "Path traversal not allowed".to_string()
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_path_valid() {
        // Use /var/run which typically exists on Unix systems
        let base = Path::new("/var/run");
        // Test base path itself
        assert!(validate_path(Path::new("/var/run"), base).is_ok(),
            "Base path should be valid");
    }

    #[test]
    fn test_validate_path_traversal() {
        let base = Path::new("/tmp");
        // These should fail because they escape /tmp
        // Note: canonicalize will fail for non-existent paths, which is ok
        assert!(validate_path(Path::new("/tmp/../etc"), base).is_err());
        assert!(validate_path(Path::new("../etc"), base).is_err());
    }

    #[test]
    fn test_chunk_entries() {
        let entries = vec![
            DirEntry {
                name: "a".to_string(),
                path: "/a".to_string(),
                is_dir: false,
                is_symlink: false,
                size: Some(100),
                modified: None,
                permissions: None,
            };
            10
        ];

        let chunks = chunk_entries(entries, 3);
        assert_eq!(chunks.len(), 4); // 10 / 3 = 4 chunks
        assert_eq!(chunks[0].len(), 3);
        assert_eq!(chunks[3].len(), 1); // last chunk has 1
    }
}
