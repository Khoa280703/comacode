//! File system watcher for VFS real-time sync
//!
//! Phase VFS-3: Monitor directory changes and push events to clients
//! Uses `notify` crate v7 for cross-platform file watching

use anyhow::{Context, Result};
use notify::{Event, EventKind, RecursiveMode, Watcher, EventHandler};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use tracing::{debug, warn};

use comacode_core::types::FileEventType;

/// Watcher ID type
pub type WatcherId = String;

/// Event handler that forwards events to a callback
struct CallbackHandler {
    watcher_id: WatcherId,
    base_path: PathBuf,
    callback: Box<dyn Fn(WatcherEvent) + Send>,
}

impl CallbackHandler {
    fn new(watcher_id: WatcherId, base_path: PathBuf, callback: Box<dyn Fn(WatcherEvent) + Send>) -> Self {
        Self { watcher_id, base_path, callback }
    }

    fn process_event(&self, event: &Event) -> Option<WatcherEvent> {
        use EventKind::*;

        let event_type = match event.kind {
            Create(_) => FileEventType::Created,
            Modify(_) => FileEventType::Modified,
            Remove(_) => FileEventType::Deleted,
            _ => return None,
        };

        let path = event.paths.first()?;
        let relative_path = path
            .strip_prefix(&self.base_path)
            .ok()
            .and_then(|p| p.to_str())
            .unwrap_or(path.to_str().unwrap_or(""));

        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        Some(WatcherEvent {
            watcher_id: self.watcher_id.clone(),
            path: relative_path.to_string(),
            event_type,
            timestamp,
        })
    }
}

impl EventHandler for CallbackHandler {
    fn handle_event(&mut self, event: Result<Event, notify::Error>) {
        match event {
            Ok(event) => {
                debug!("📁 [Watcher] Event: {:?} at {:?}", event.kind, event.paths);
                if let Some(fe) = self.process_event(&event) {
                    (self.callback)(fe);
                }
            }
            Err(e) => {
                warn!("📁 [Watcher] Error: {:?}", e);
            }
        }
    }
}

/// Active watcher instance
struct ActiveWatcher {
    _watcher: notify::RecommendedWatcher,
    path: String,
}

/// Manager for file system watchers
///
/// Phase VFS-3: Handles directory watching
pub struct WatcherManager {
    watchers: Arc<Mutex<HashMap<String, ActiveWatcher>>>,
}

impl WatcherManager {
    /// Create new watcher manager
    pub fn new() -> Self {
        Self {
            watchers: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Start watching a directory
    ///
    /// Returns watcher_id for later cancellation
    pub async fn watch_directory(
        &self,
        watcher_id: String,
        path: &Path,
        on_event: impl Fn(WatcherEvent) + Send + 'static,
    ) -> Result<()> {
        let path = path.to_path_buf();

        // Verify directory exists
        if !path.exists() {
            return Err(anyhow::anyhow!("Path does not exist: {}", path.display()));
        }

        if !path.is_dir() {
            return Err(anyhow::anyhow!("Path is not a directory: {}", path.display()));
        }

        tracing::info!("📁 [Watcher] Starting watch: {} ({})", path.display(), watcher_id);

        // Create watcher with our handler
        let mut watcher = notify::recommended_watcher(CallbackHandler::new(
            watcher_id.clone(),
            path.clone(),
            Box::new(on_event),
        ))
            .context("Failed to create file watcher")?;

        watcher.watch(&path, RecursiveMode::NonRecursive)?;

        // Store active watcher
        self.watchers.lock().await.insert(
            watcher_id.clone(),
            ActiveWatcher {
                _watcher: watcher,
                path: path.to_string_lossy().to_string(),
            },
        );

        tracing::info!("📁 [Watcher] Watch started successfully: {}", watcher_id);
        Ok(())
    }

    /// Stop watching a directory
    pub async fn unwatch(&self, watcher_id: &str) -> Result<()> {
        tracing::info!("📁 [Watcher] Stopping watch: {}", watcher_id);

        let mut watchers = self.watchers.lock().await;
        if watchers.remove(watcher_id).is_some() {
            Ok(())
        } else {
            Err(anyhow::anyhow!("Watcher not found: {}", watcher_id))
        }
    }
}

impl Default for WatcherManager {
    fn default() -> Self {
        Self::new()
    }
}

/// File event produced by watcher
///
/// Public struct for callback
#[derive(Debug, Clone)]
pub struct WatcherEvent {
    pub watcher_id: String,
    pub path: String,
    pub event_type: FileEventType,
    pub timestamp: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_watcher_manager_new() {
        let mgr = WatcherManager::new();
        let _ = &mgr.watchers;
    }
}
