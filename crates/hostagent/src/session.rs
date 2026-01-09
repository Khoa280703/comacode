//! Session management for multiple PTY instances
//!
//! Manages lifecycle of PTY sessions with automatic cleanup.

use anyhow::{Context, Result};
use bytes::Bytes;
use crate::pty::PtySession;
use comacode_core::terminal::TerminalConfig;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::AsyncReadExt;
use tokio::sync::{mpsc, Mutex};
use tokio_stream::StreamExt;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::io::StreamReader;

/// Session manager for PTY instances
pub struct SessionManager {
    /// Active sessions (ID -> PTY)
    sessions: Arc<Mutex<HashMap<u64, Arc<Mutex<PtySession>>>>>,
    /// Output receivers (ID -> Receiver)
    outputs: Arc<Mutex<HashMap<u64, mpsc::Receiver<Bytes>>>>,
    /// Next session ID
    next_id: Arc<AtomicU64>,
}

impl SessionManager {
    /// Create new session manager
    pub fn new() -> Self {
        Self {
            sessions: Default::default(),
            outputs: Default::default(),
            next_id: Arc::new(AtomicU64::new(1)),
        }
    }

    /// Create new PTY session
    pub async fn create_session(&self, config: TerminalConfig) -> Result<u64> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (session, output_rx) = PtySession::spawn(id, config)
            .with_context(|| format!("Failed to create PTY session {}", id))?;

        let mut sessions = self.sessions.lock().await;
        let mut outputs = self.outputs.lock().await;

        sessions.insert(id, session);
        outputs.insert(id, output_rx);

        tracing::info!("Created PTY session {}", id);
        Ok(id)
    }

    /// Get session by ID
    #[allow(dead_code)]
    pub async fn get_session(&self, id: u64) -> Option<Arc<Mutex<PtySession>>> {
        let sessions = self.sessions.lock().await;
        sessions.get(&id).cloned()
    }

    /// Write to session
    pub async fn write_to_session(&self, id: u64, data: &[u8]) -> Result<()> {
        let sessions = self.sessions.lock().await;
        if let Some(session) = sessions.get(&id) {
            let mut sess = session.lock().await;
            sess.write(data)
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Resize session
    pub async fn resize_session(&self, id: u64, rows: u16, cols: u16) -> Result<()> {
        let sessions = self.sessions.lock().await;
        if let Some(session) = sessions.get(&id) {
            let mut sess = session.lock().await;
            sess.resize(rows, cols)
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Cleanup (remove) session
    pub async fn cleanup_session(&self, id: u64) -> Result<()> {
        let mut sessions = self.sessions.lock().await;
        let mut outputs = self.outputs.lock().await;

        if let Some(session) = sessions.remove(&id) {
            tracing::info!("Cleaning up PTY session {}", id);
            let mut sess = session.lock().await;

            // Explicitly kill child process
            if let Err(e) = sess.kill() {
                tracing::warn!("Failed to kill session {} process: {}", id, e);
            }

            // Remove output receiver
            outputs.remove(&id);

            drop(sess);
            Ok(())
        } else {
            Err(anyhow::anyhow!("Session {} not found", id))
        }
    }

    /// Get all active session IDs
    #[allow(dead_code)]
    pub async fn list_sessions(&self) -> Vec<u64> {
        let sessions = self.sessions.lock().await;
        sessions.keys().copied().collect()
    }

    /// Get session count
    #[allow(dead_code)]
    pub async fn session_count(&self) -> usize {
        let sessions = self.sessions.lock().await;
        sessions.len()
    }

    /// Get output sender for a session (for forwarding PTY output)
    pub async fn get_session_output(&self, id: u64) -> Option<tokio::sync::mpsc::Sender<bytes::Bytes>> {
        let sessions = self.sessions.lock().await;
        if let Some(session) = sessions.get(&id) {
            let sess = session.lock().await;
            Some(sess.output_sender())
        } else {
            None
        }
    }

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

    /// Remove dead sessions
    async fn cleanup_dead_sessions(&self) {
        let mut sessions = self.sessions.lock().await;
        let mut outputs = self.outputs.lock().await;
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
            tracing::info!("Auto-cleaning dead session {}", id);
            sessions.remove(&id);
            outputs.remove(&id);
        }
    }

    /// Get PTY output as AsyncRead for QUIC forwarding
    ///
    /// This is the key method for Phase 05.1 integration.
    /// Uses tokio utilities to convert the mpsc channel to AsyncRead.
    ///
    /// Returns None if session not found or receiver already taken.
    pub async fn get_pty_reader(&self, session_id: u64) -> Option<impl AsyncReadExt + Unpin + Send> {
        let mut outputs = self.outputs.lock().await;
        let rx = outputs.remove(&session_id)?;

        // Channel -> Stream -> AsyncRead (using tokio utilities)
        let stream = ReceiverStream::new(rx).map(Ok::<_, std::io::Error>);
        Some(StreamReader::new(stream))
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}
