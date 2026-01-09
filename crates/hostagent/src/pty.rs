//! PTY session management using portable-pty
//!
//! Provides cross-platform PTY spawning and I/O handling for terminal sessions.
//! Uses channel-based architecture with spawn_blocking for PTY reader.

use anyhow::{Context, Result};
use bytes::Bytes;
use comacode_core::terminal::TerminalConfig;
use comacode_core::OutputStream;
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::Read;
use std::sync::Arc;
use tokio::sync::Mutex;

/// PTY session wrapper
pub struct PtySession {
    /// PTY master handle
    _master: Box<dyn portable_pty::MasterPty + Send>,
    /// Child process handle
    child: Box<dyn portable_pty::Child + Send>,
    /// Session ID
    #[allow(dead_code)]
    id: u64,
    /// Current terminal size
    #[allow(dead_code)]
    size: (u16, u16),
    /// Writer handle
    writer: Box<dyn std::io::Write + Send>,
    /// Output stream sender
    output_tx: tokio::sync::mpsc::Sender<Bytes>,
}

// Implement Send manually
unsafe impl Send for PtySession {}

impl PtySession {
    /// Spawn new PTY session with channel-based output streaming
    ///
    /// Returns `(Arc<Mutex<PtySession>>, Receiver<Bytes>)` where the receiver
    /// can be converted to AsyncRead for QUIC forwarding.
    pub fn spawn(id: u64, config: TerminalConfig) -> Result<(Arc<Mutex<Self>>, tokio::sync::mpsc::Receiver<Bytes>)> {
        let pty_system = native_pty_system();

        let pty_size = PtySize {
            rows: config.rows,
            cols: config.cols,
            pixel_width: 0,
            pixel_height: 0,
        };

        let pty_pair = pty_system
            .openpty(pty_size)
            .context("Failed to open PTY")?;

        // Build command with shell and env
        let mut cmd = CommandBuilder::new(config.shell.clone());
        for (key, value) in &config.env {
            cmd.env(key, value);
        }

        let child = pty_pair
            .slave
            .spawn_command(cmd)
            .context("Failed to spawn shell")?;

        // Get writer from master
        let writer = pty_pair.master.take_writer()?;

        // Create bounded output stream (channel capacity = 1024 messages)
        let (output_stream, output_rx) = OutputStream::new(1024);
        let output_tx = output_stream.sender();

        // PTY Reader Task: Uses spawn_blocking for blocking I/O
        // QUAN TRỌNG: portable-pty.read() is blocking - must use spawn_blocking
        let reader = pty_pair.master.try_clone_reader()?;
        let tx_clone = output_tx.clone();
        let session_id = id;

        let pty_reader = tokio::task::spawn_blocking(move || {
            let mut reader = reader;
            let mut buf = [0u8; 8192];

            loop {
                // Blocking read - blocks this thread but NOT the Tokio runtime
                match reader.read(&mut buf) {
                    Ok(0) => {
                        tracing::debug!("PTY reader EOF for session {}", session_id);
                        break;
                    }
                    Ok(n) => {
                        // Zero-cost conversion to Bytes (shares buffer if possible)
                        let data = Bytes::copy_from_slice(&buf[..n]);

                        // Blocking send OK because we're in spawn_blocking thread
                        match tx_clone.blocking_send(data) {
                            Ok(_) => {
                                // Log if send succeeds (backpressure is handled by blocking)
                                tracing::trace!("PTY output sent: {} bytes for session {}", n, session_id);
                            }
                            Err(_) => {
                                tracing::warn!("Output stream closed for session {}", session_id);
                                break;
                            }
                        }
                    }
                    Err(e) => {
                        tracing::error!("PTY read error for session {}: {}", session_id, e);
                        break;
                    }
                }
            }
            Ok::<(), anyhow::Error>(())
        });

        // Log reader task completion
        tokio::spawn(async move {
            match pty_reader.await {
                Ok(Ok(_)) => tracing::debug!("PTY reader task completed for session {}", session_id),
                Ok(Err(e)) => tracing::error!("PTY reader task error for session {}: {}", session_id, e),
                Err(e) => tracing::error!("PTY reader task panicked for session {}: {}", session_id, e),
            }
        });

        let session = Arc::new(Mutex::new(Self {
            _master: pty_pair.master,
            child,
            id,
            size: (config.rows, config.cols),
            writer,
            output_tx,
        }));

        tracing::info!(
            "PTY session {} spawned with shell {} (channel-based streaming)",
            id,
            config.shell
        );
        Ok((session, output_rx))
    }

    /// Get session ID
    #[allow(dead_code)]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Write data to PTY input
    pub fn write(&mut self, data: &[u8]) -> Result<()> {
        use std::io::Write;
        self.writer
            .write_all(data)
            .context("Failed to write to PTY")?;
        self.writer
            .flush()
            .context("Failed to flush PTY writer")?;
        Ok(())
    }

    /// Resize terminal
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        let size = PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        };
        self._master
            .resize(size)
            .context("Failed to resize PTY")?;
        self.size = (rows, cols);
        Ok(())
    }

    /// Get current size
    #[allow(dead_code)]
    pub fn size(&self) -> (u16, u16) {
        self.size
    }

    /// Check if process is still alive
    pub fn is_alive(&mut self) -> bool {
        match self.child.try_wait() {
            Ok(None) => true,   // Process still running
            Ok(Some(_)) => false, // Process exited
            Err(_) => false,    // Error - treat as dead
        }
    }

    /// Kill child process explicitly
    pub fn kill(&mut self) -> Result<()> {
        self.child
            .kill()
            .map_err(|e| anyhow::anyhow!("Failed to kill process: {}", e))?;
        Ok(())
    }

    /// Get output stream sender for external forwarding
    ///
    /// This allows the QUIC server to subscribe to PTY output.
    pub fn output_sender(&self) -> tokio::sync::mpsc::Sender<Bytes> {
        self.output_tx.clone()
    }

    /// Subscribe to PTY output stream (creates new receiver)
    ///
    /// Note: This is a convenience method that creates a new subscription.
    /// For production, use output_sender() directly for better performance.
    ///
    /// # Warning
    /// This method returns a dummy receiver for MVP.
    /// In Phase 03, we'll implement proper broadcast channel for multi-consumer support.
    #[allow(dead_code)]
    pub fn subscribe_output(&self) -> tokio::sync::broadcast::Receiver<Bytes> {
        // For MVP, return a dummy receiver
        // In Phase 03, we'll implement proper broadcast channel
        let (_tx, rx) = tokio::sync::broadcast::channel(1024);
        rx
    }
}
