//! Mobile bridge output streaming
//!
//! Handles PTY output forwarding from Rust to Flutter UI via channel-based architecture.
//! Similar to hostagent but optimized for mobile use case.

use bytes::Bytes;
use comacode_core::OutputStream;
use flutter_rust_bridge::frb;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Output stream handler for mobile terminal UI
///
/// Manages channel-based streaming of PTY output to Flutter.
pub struct MobileTerminalStream {
    /// Output stream for PTY data
    output_stream: OutputStream,
    /// Receiver for consuming PTY output
    _rx: tokio::sync::mpsc::Receiver<Bytes>,
}

impl MobileTerminalStream {
    /// Create new mobile terminal stream
    pub fn new(capacity: usize) -> Self {
        let (output_stream, rx) = OutputStream::new(capacity);
        Self {
            output_stream,
            _rx: rx,
        }
    }

    /// Send PTY output data to Flutter UI
    pub async fn send_output(&self, data: Bytes) -> Result<(), String> {
        self.output_stream
            .send(data)
            .await
            .map_err(|e| format!("Failed to send output: {}", e))
    }

    /// Get output stream sender for external use
    pub fn sender(&self) -> tokio::sync::mpsc::Sender<Bytes> {
        self.output_stream.sender()
    }

    /// Check buffer capacity for backpressure monitoring
    pub fn remaining_capacity(&self) -> usize {
        self.output_stream.remaining()
    }
}

/// Shared mobile terminal stream manager
pub struct MobileStreamManager {
    streams: Arc<Mutex<std::collections::HashMap<u64, Arc<MobileTerminalStream>>>>,
}

impl MobileStreamManager {
    /// Create new stream manager
    pub fn new() -> Self {
        Self {
            streams: Arc::new(Mutex::new(std::collections::HashMap::new())),
        }
    }

    /// Register new terminal session
    pub async fn register_session(&self, session_id: u64) -> Arc<MobileTerminalStream> {
        let stream = Arc::new(MobileTerminalStream::new(1024));
        let mut streams = self.streams.lock().await;
        streams.insert(session_id, stream.clone());
        stream
    }

    /// Get stream for session
    pub async fn get_stream(&self, session_id: u64) -> Option<Arc<MobileTerminalStream>> {
        let streams = self.streams.lock().await;
        streams.get(&session_id).cloned()
    }

    /// Unregister session
    pub async fn unregister_session(&self, session_id: u64) {
        let mut streams = self.streams.lock().await;
        streams.remove(&session_id);
    }
}

impl Default for MobileStreamManager {
    fn default() -> Self {
        Self::new()
    }
}

// Flutter-friendly FFI functions

/// Create output stream for a terminal session
#[frb]
pub async fn create_output_stream(session_id: u64) -> String {
    // For now, return session ID as confirmation
    // In production, this would return a stream handle
    format!("Stream created for session {}", session_id)
}

/// Send terminal output data (from PTY) to stream
#[frb]
pub async fn send_terminal_output(session_id: u64, data: Vec<u8>) -> Result<(), String> {
    // For MVP, just log the data
    // In production, this would send to the actual stream
    tracing::trace!(
        "Terminal output for session {}: {} bytes",
        session_id,
        data.len()
    );
    Ok(())
}

/// Get current buffer capacity for backpressure monitoring
#[frb]
pub async fn get_buffer_capacity(_session_id: u64) -> usize {
    // For MVP, return default capacity
    // In production, this would query actual stream
    1024
}

/// Get remaining buffer slots
#[frb]
pub async fn get_remaining_capacity(_session_id: u64) -> usize {
    // For MVP, return full capacity
    // In production, this would query actual stream
    1024
}
