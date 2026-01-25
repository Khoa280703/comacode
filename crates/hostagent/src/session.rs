//! Session management for multiple PTY instances
//!
//! Manages lifecycle of PTY sessions with automatic cleanup.
//! Phase 04: Extended to support UUID-based sessions with history buffers.

use anyhow::{Context, Result};
use bytes::Bytes;
use crate::pty::PtySession;
use comacode_core::terminal::TerminalConfig;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::AsyncReadExt;
use tokio::sync::{mpsc, Mutex};
use tokio_stream::StreamExt;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::io::StreamReader;

/// Session data with UUID key (Phase 04)
#[allow(dead_code)]  // Phase 04: Fields used for future history tracking
pub struct SessionData {
    /// PTY session handle
    pub pty_session: Arc<Mutex<PtySession>>,
    /// History buffer (last 100 lines) for inactive sessions
    pub history: VecDeque<String>,
    /// History channel receiver (for pump task to push lines)
    history_rx: tokio::sync::mpsc::Receiver<String>,
    /// Terminal configuration
    pub config: TerminalConfig,
    /// Working directory (project path)
    pub working_dir: String,
}

#[allow(dead_code)]  // Phase 04: API methods used by mobile bridge
impl SessionData {
    /// Create new session data
    pub fn new(
        pty_session: Arc<Mutex<PtySession>>,
        config: TerminalConfig,
        working_dir: String,
        history_rx: tokio::sync::mpsc::Receiver<String>,
    ) -> Self {
        Self {
            pty_session,
            history: VecDeque::with_capacity(100),
            history_rx,
            config,
            working_dir,
        }
    }

    /// Add line to history (max 100 lines)
    pub fn add_history_line(&mut self, line: String) {
        if self.history.len() >= 100 {
            self.history.pop_front();
        }
        self.history.push_back(line);
    }
}

/// Session manager for PTY instances
pub struct SessionManager {
    /// Active sessions (legacy u64 ID -> PTY)
    /// Phase 04: Kept for backward compatibility during transition
    sessions_legacy: Arc<Mutex<HashMap<u64, Arc<Mutex<PtySession>>>>>,
    /// Output receivers (legacy u64 ID -> Receiver)
    outputs_legacy: Arc<Mutex<HashMap<u64, mpsc::Receiver<Bytes>>>>,
    /// Next session ID (legacy)
    next_id: Arc<AtomicU64>,

    /// UUID-based sessions (Phase 04)
    sessions_uuid: Arc<Mutex<HashMap<String, SessionData>>>,

    /// History senders for pump tasks (Phase 04: P0 fix)
    /// Maps session_id -> history channel sender
    history_senders: Arc<Mutex<HashMap<String, tokio::sync::mpsc::Sender<String>>>>,
}

impl SessionManager {
    /// Create new session manager
    pub fn new() -> Self {
        Self {
            sessions_legacy: Default::default(),
            outputs_legacy: Default::default(),
            next_id: Arc::new(AtomicU64::new(1)),
            sessions_uuid: Default::default(),
            history_senders: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    // ===== Legacy u64-based API (backward compatibility) =====

    /// Create new PTY session (legacy)
    pub async fn create_session(&self, config: TerminalConfig) -> Result<u64> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (session, output_rx) = PtySession::spawn(id, config)
            .with_context(|| format!("Failed to create PTY session {}", id))?;

        let mut sessions = self.sessions_legacy.lock().await;
        let mut outputs = self.outputs_legacy.lock().await;

        sessions.insert(id, session);
        outputs.insert(id, output_rx);

        tracing::info!("Created PTY session {}", id);
        Ok(id)
    }

    /// Get session by ID (legacy)
    #[allow(dead_code)]
    pub async fn get_session(&self, id: u64) -> Option<Arc<Mutex<PtySession>>> {
        let sessions = self.sessions_legacy.lock().await;
        sessions.get(&id).cloned()
    }

    /// Write to session (legacy)
    pub async fn write_to_session(&self, id: u64, data: &[u8]) -> Result<()> {
        let sessions = self.sessions_legacy.lock().await;
        if let Some(session) = sessions.get(&id) {
            let mut sess = session.lock().await;
            sess.write(data)
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Resize session (legacy)
    pub async fn resize_session(&self, id: u64, rows: u16, cols: u16) -> Result<()> {
        let sessions = self.sessions_legacy.lock().await;
        if let Some(session) = sessions.get(&id) {
            let mut sess = session.lock().await;
            sess.resize(rows, cols)
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Cleanup (remove) session (legacy)
    pub async fn cleanup_session(&self, id: u64) -> Result<()> {
        let mut sessions = self.sessions_legacy.lock().await;
        let mut outputs = self.outputs_legacy.lock().await;

        if let Some(session) = sessions.remove(&id) {
            tracing::info!("Cleaning up PTY session {}", id);
            let mut sess = session.lock().await;

            if let Err(e) = sess.kill() {
                tracing::warn!("Failed to kill session {} process: {}", id, e);
            }

            outputs.remove(&id);

            drop(sess);
            Ok(())
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Get all active session IDs (legacy)
    #[allow(dead_code)]
    pub async fn list_sessions(&self) -> Vec<u64> {
        let sessions = self.sessions_legacy.lock().await;
        sessions.keys().copied().collect()
    }

    /// Get session count (legacy)
    #[allow(dead_code)]
    pub async fn session_count(&self) -> usize {
        let sessions = self.sessions_legacy.lock().await;
        sessions.len()
    }

    /// Get PTY output as AsyncRead for QUIC forwarding (legacy)
    pub async fn get_pty_reader(&self, session_id: u64) -> Option<impl AsyncReadExt + Unpin + Send> {
        let mut outputs = self.outputs_legacy.lock().await;
        let rx = outputs.remove(&session_id)?;

        let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
        Some(StreamReader::new(stream))
    }

    // ===== UUID-based API (Phase 04: Multi-Session Support) =====

    /// Create session with UUID from mobile
    /// Phase 04: Project & Session Management
    ///
    /// Creates PTY session and spawns background history capture task.
    pub async fn create_session_with_uuid(
        &self,
        session_id: String,
        config: TerminalConfig,
        working_dir: &str,
    ) -> Result<()> {
        // Spawn PTY with temporary u64 ID (internally)
        let temp_id = self.next_id.fetch_add(1, Ordering::SeqCst);

        // Build shell command with working directory
        let shell_cmd = format!("cd {} && claude", working_dir);
        let mut config_with_dir = config.clone();
        config_with_dir.shell = shell_cmd;

        let (session, _output_rx) = PtySession::spawn(temp_id, config_with_dir.clone())
            .with_context(|| format!("Failed to create PTY session {}", session_id))?;

        // Create history channel (buffer 100 lines, non-blocking)
        let (history_tx, history_rx) = tokio::sync::mpsc::channel::<String>(100);

        let session_key = session_id.clone();
        let mut sessions = self.sessions_uuid.lock().await;
        let session_data = SessionData::new(
            session,
            config_with_dir,
            working_dir.to_string(),
            history_rx,
        );

        // Spawn background history capture task
        let sessions_arc = self.sessions_uuid.clone();
        tokio::spawn(async move {
            let mut history_rx = {
                // Get the history receiver from the session
                let mut sessions = sessions_arc.lock().await;
                if let Some(sd) = sessions.get_mut(&session_key) {
                    // Take the receiver and replace with a dummy one
                    let (_tx, new_rx) = tokio::sync::mpsc::channel::<String>(1);
                    std::mem::replace(&mut sd.history_rx, new_rx)
                } else {
                    return; // Session no longer exists
                }
            };

            // Capture history lines and populate buffer
            while let Some(line) = history_rx.recv().await {
                let mut sessions = sessions_arc.lock().await;
                if let Some(sd) = sessions.get_mut(&session_key) {
                    sd.add_history_line(line);
                }
            }
        });

        // Store history_tx for pump tasks to access
        let mut history_senders = self.history_senders.lock().await;
        history_senders.insert(session_id.clone(), history_tx);

        sessions.insert(session_id.clone(), session_data);
        tracing::info!("Created PTY session with UUID {}", session_id);
        Ok(())
    }

    /// Check if session exists (for re-attach logic)
    pub async fn session_exists(&self, session_id: &str) -> bool {
        let sessions = self.sessions_uuid.lock().await;
        sessions.contains_key(session_id)
    }

    /// Get history buffer for session
    pub async fn get_history(&self, session_id: &str) -> Vec<String> {
        let sessions = self.sessions_uuid.lock().await;
        sessions
            .get(session_id)
            .map(|s| s.history.iter().cloned().collect())
            .unwrap_or_default()
    }

    /// Add line to history (max 100 lines)
    #[allow(dead_code)]  // Phase 04: Used for history tracking
    pub async fn add_to_history(&self, session_id: &str, line: String) {
        let mut sessions = self.sessions_uuid.lock().await;
        if let Some(session) = sessions.get_mut(session_id) {
            session.add_history_line(line);
        }
    }

    /// Get PTY session by UUID for direct operations
    #[allow(dead_code)]  // Phase 04: API method for mobile bridge
    pub async fn get_uuid_session(&self, session_id: &str) -> Option<Arc<Mutex<PtySession>>> {
        let sessions = self.sessions_uuid.lock().await;
        sessions.get(session_id).map(|s| s.pty_session.clone())
    }

    /// Write to UUID session
    pub async fn write_to_uuid_session(&self, session_id: &str, data: &[u8]) -> Result<()> {
        let sessions = self.sessions_uuid.lock().await;
        if let Some(session_data) = sessions.get(session_id) {
            let mut sess = session_data.pty_session.lock().await;
            sess.write(data)
        } else {
            Err(anyhow::anyhow!("Session {} not found", session_id))
        }
    }

    /// Resize UUID session
    pub async fn resize_uuid_session(&self, session_id: &str, rows: u16, cols: u16) -> Result<()> {
        let sessions = self.sessions_uuid.lock().await;
        if let Some(session_data) = sessions.get(session_id) {
            let mut sess = session_data.pty_session.lock().await;
            sess.resize(rows, cols)
        } else {
            Err(anyhow::anyhow!("Session {} not found", session_id))
        }
    }

    /// Close UUID session
    pub async fn close_session(&self, session_id: &str) -> Result<()> {
        let mut sessions = self.sessions_uuid.lock().await;

        if let Some(session_data) = sessions.remove(session_id) {
            tracing::info!("Closing PTY session {}", session_id);
            let mut sess = session_data.pty_session.lock().await;

            if let Err(e) = sess.kill() {
                tracing::warn!("Failed to kill session {} process: {}", session_id, e);
            }

            drop(sess);

            // Clean up history sender
            let mut history_senders = self.history_senders.lock().await;
            history_senders.remove(session_id);

            Ok(())
        } else {
            Err(anyhow::anyhow!("Session {} not found", session_id))
        }
    }

    /// Get history sender for pump task (Phase 04: P0 fix)
    pub async fn get_history_sender(&self, session_id: &str) -> Option<tokio::sync::mpsc::Sender<String>> {
        let history_senders = self.history_senders.lock().await;
        history_senders.get(session_id).cloned()
    }

    /// List all UUID session IDs
    pub async fn list_uuid_sessions(&self) -> Vec<String> {
        let sessions = self.sessions_uuid.lock().await;
        sessions.keys().cloned().collect()
    }

    /// Get UUID session count
    #[allow(dead_code)]  // Phase 04: API method for mobile bridge
    pub async fn uuid_session_count(&self) -> usize {
        let sessions = self.sessions_uuid.lock().await;
        sessions.len()
    }

    // ===== Shared cleanup =====

    /// Cleanup task that periodically removes dead sessions
    pub fn spawn_cleanup_task(self: Arc<Self>) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(30));
            loop {
                interval.tick().await;
                self.cleanup_dead_sessions().await;
            }
        })
    }

    /// Remove dead sessions (both legacy and UUID)
    async fn cleanup_dead_sessions(&self) {
        // Cleanup legacy sessions
        {
            let mut sessions = self.sessions_legacy.lock().await;
            let mut outputs = self.outputs_legacy.lock().await;
            let dead_ids: Vec<u64> = {
                let mut dead = Vec::new();
                for (id, session) in sessions.iter() {
                    let mut sess = session.lock().await;
                    if !sess.is_alive() {
                        dead.push(*id);
                    }
                }
                dead
            };

            for id in dead_ids {
                tracing::info!("Auto-cleaning dead legacy session {}", id);
                sessions.remove(&id);
                outputs.remove(&id);
            }
        }

        // Cleanup UUID sessions
        {
            let mut sessions = self.sessions_uuid.lock().await;
            let dead_ids: Vec<String> = {
                let mut dead = Vec::new();
                for (id, session_data) in sessions.iter() {
                    let mut sess = session_data.pty_session.lock().await;
                    if !sess.is_alive() {
                        dead.push(id.clone());
                    }
                }
                dead
            };

            for id in dead_ids {
                tracing::info!("Auto-cleaning dead UUID session {}", id);
                sessions.remove(&id);
            }
        }
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}
