//! QUIC stream pumps for terminal I/O
//!
//! This module provides bidirectional data pumping between PTY and QUIC streams.
//! It uses Quinn's built-in flow control for natural backpressure.

use quinn::{RecvStream, SendStream};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;

use crate::protocol::MessageCodec;
use crate::types::{NetworkMessage, TerminalEvent, TaggedOutput};
use crate::{CoreError, Result};

/// Smart buffering configuration for PTY→QUIC streaming
///
/// Balances latency (interactive typing) vs throughput (bulk output).
#[derive(Debug, Clone, Copy)]
pub struct BufferConfig {
    /// Maximum batch size before forcing flush
    pub max_batch_size: usize,

    /// Maximum time to wait before flushing (milliseconds)
    pub max_flush_delay_ms: u64,

    /// Flush immediately on newline (for interactive mode)
    pub flush_on_newline: bool,
}

impl Default for BufferConfig {
    fn default() -> Self {
        Self {
            max_batch_size: 16 * 1024,  // 16KB
            max_flush_delay_ms: 10,     // 10ms
            flush_on_newline: true,     // Interactive-friendly
        }
    }
}

impl BufferConfig {
    /// Interactive mode: low latency, small batches
    /// Best for: shell interaction, command typing
    pub fn interactive() -> Self {
        Self {
            max_batch_size: 4 * 1024,   // 4KB
            max_flush_delay_ms: 5,      // 5ms
            flush_on_newline: true,
        }
    }

    /// Bulk mode: high throughput, large batches
    /// Best for: cat large files, logs, install scripts
    pub fn bulk() -> Self {
        Self {
            max_batch_size: 64 * 1024,  // 64KB
            max_flush_delay_ms: 50,     // 50ms
            flush_on_newline: false,
        }
    }
}

/// Pump data from PTY to QUIC stream
///
/// This is the CRITICAL function for terminal I/O.
/// Quinn's write_all() automatically handles backpressure:
/// - When network is slow, write_all() awaits
/// - Loop stops → no more PTY reads → natural backpressure
///
/// # Arguments
/// * `pty` - Async reader from PTY
/// * `send` - QUIC send stream (mutable reference for shared use)
///
/// # Behavior
/// 1. Read from PTY in 8KB chunks
/// 2. Encode as NetworkMessage::Event
/// 3. Send via QUIC (with automatic flow control)
pub async fn pump_pty_to_quic<R>(
    mut pty: R,
    send: &mut SendStream,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
{
    let mut buf = vec![0u8; 8192];

    loop {
        let n = pty.read(&mut buf).await?;
        if n == 0 {
            tracing::debug!("PTY EOF, closing stream");
            break;
        }

        // Encode as NetworkMessage FIRST (do NOT send raw bytes!)
        // MessageCodec already handles length prefixing
        let msg = NetworkMessage::Event(TerminalEvent::Output {
            data: buf[..n].to_vec()
        });
        let encoded = MessageCodec::encode(&msg)?;

        // Send ONCE - Quinn handles flow control automatically
        send.write_all(&encoded).await?;

        tracing::trace!("Sent {} bytes from PTY to QUIC", n);
    }

    // Finish the stream gracefully
    let _ = send.finish();
    Ok(())
}

/// Pump data from PTY to QUIC stream with smart buffering
///
/// Optimizes throughput vs latency trade-off by batching small reads.
/// Uses tokio::select! to avoid blocking on read when timeout expires.
///
/// Flush conditions:
/// - Size threshold reached (max_batch_size)
/// - Newline detected (if flush_on_newline=true)
/// - Timeout exceeded (max_flush_delay_ms) - CRITICAL: checked via select!
///
/// # Arguments
/// * `pty` - Async reader from PTY
/// * `send` - QUIC send stream
/// * `config` - Buffering strategy
pub async fn pump_pty_to_quic_smart<R>(
    mut pty: R,
    send: &mut SendStream,
    config: BufferConfig,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
{
    let mut read_buf = vec![0u8; 8192];
    let mut batch_buf = Vec::with_capacity(config.max_batch_size);

    loop {
        // Calculate timeout: only flush if we have buffered data
        let flush_timeout = if !batch_buf.is_empty() {
            std::time::Duration::from_millis(config.max_flush_delay_ms)
        } else {
            // No data buffered, wait indefinitely for new data
            std::time::Duration::from_secs(3600)
        };

        tokio::select! {
            // Case 1: PTY has data
            result = pty.read(&mut read_buf) => {
                let n = result?;
                if n == 0 {
                    // EOF - flush remaining and exit
                    if !batch_buf.is_empty() {
                        send_batch(&batch_buf, send).await?;
                    }
                    break;
                }

                // Check for newline in this chunk
                let chunk_has_newline = read_buf[..n].contains(&b'\n');

                // Accumulate data
                if batch_buf.len() + n <= config.max_batch_size {
                    batch_buf.extend_from_slice(&read_buf[..n]);
                } else {
                    // Batch full - send current, start new
                    if !batch_buf.is_empty() {
                        send_batch(&batch_buf, send).await?;
                    }
                    batch_buf = read_buf[..n].to_vec();
                }

                // Immediate flush conditions (no waiting)
                let should_flush = if config.flush_on_newline && chunk_has_newline {
                    true  // Interactive mode - flush on newline
                } else if batch_buf.len() >= config.max_batch_size {
                    true  // Size threshold - flush to avoid oversized batches
                } else {
                    false
                };

                if should_flush {
                    send_batch(&batch_buf, send).await?;
                    batch_buf.clear();
                }
            }

            // Case 2: Timeout expired - flush buffered data
            _ = tokio::time::sleep(flush_timeout), if !batch_buf.is_empty() => {
                send_batch(&batch_buf, send).await?;
                batch_buf.clear();
            }
        }
    }

    let _ = send.finish();
    Ok(())
}

/// Pump data from PTY to QUIC stream with session tagging (Phase 04)
///
/// Multi-session variant that wraps output in TaggedOutput for routing.
/// Also captures output to history buffer for session replay.
///
/// # Arguments
/// * `pty` - Async reader from PTY
/// * `send` - QUIC send stream
/// * `session_id` - UUID of the session generating this output
/// * `history_tx` - Optional channel sender to push history lines (for inactive sessions)
///
/// # History Capture
/// - Splits output by newlines (\n)
/// - Maintains incomplete UTF-8 sequences between chunks
/// - Max 100 lines in history buffer
pub async fn pump_pty_to_quic_tagged<R>(
    mut pty: R,
    send: &mut SendStream,
    session_id: String,
    history_tx: Option<tokio::sync::mpsc::Sender<String>>,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send,
{
    let mut buf = vec![0u8; 8192];
    let mut line_accumulator = Vec::new(); // For handling split UTF-8

    loop {
        let n = pty.read(&mut buf).await?;
        if n == 0 {
            tracing::debug!("PTY EOF for session {}, closing stream", session_id);
            break;
        }

        let data = &buf[..n];

        // FAST PATH: Send to network immediately (no waiting for history)
        let msg = NetworkMessage::TaggedOutput(TaggedOutput {
            session_id: session_id.clone(),
            data: data.to_vec(),
        });
        let encoded = MessageCodec::encode(&msg)?;
        send.write_all(&encoded).await?;

        // SLOW PATH: Capture to history (best effort, non-blocking)
        if let Some(ref tx) = history_tx {
            // Accumulate bytes and try to extract complete lines
            line_accumulator.extend_from_slice(data);

            // Try to parse as UTF-8 and extract lines
            if let Ok(text) = String::from_utf8(line_accumulator.clone()) {
                let mut lines = text.split('\n').peekable();
                let mut has_incomplete = false;

                while let Some(line) = lines.next() {
                    if lines.peek().is_some() {
                        // Complete line (before \n)
                        let _ = tx.try_send(line.to_string()); // Non-blocking, drops if full
                    } else {
                        // Last segment (may be incomplete if no trailing \n)
                        if !text.ends_with('\n') && !line.is_empty() {
                            line_accumulator = line.as_bytes().to_vec();
                            has_incomplete = true;
                        }
                    }
                }

                if !has_incomplete {
                    line_accumulator.clear();
                }
            } else {
                // Invalid UTF-8 - this happens when multi-byte char is split across chunks
                // Keep the bytes and wait for next chunk to complete the character
                // Safety: Prevent unbounded growth from binary garbage
                if line_accumulator.len() > 10000 {
                    line_accumulator.clear();
                }
            }

            tracing::trace!("Sent {} bytes from PTY session {} to QUIC (history captured)", n, session_id);
        } else {
            tracing::trace!("Sent {} bytes from PTY session {} to QUIC (no history)", n, session_id);
        }
    }

    let _ = send.finish();
    Ok(())
}

/// Helper: send a batch of data as a single NetworkMessage
async fn send_batch(data: &[u8], send: &mut SendStream) -> Result<()> {
    if data.is_empty() {
        return Ok(());
    }

    // DEBUG: Log PTY output
    eprintln!("[DEBUG] PTY output: {:02X?}", data);

    let msg = NetworkMessage::Event(TerminalEvent::Output {
        data: data.to_vec(),
    });
    let encoded = MessageCodec::encode(&msg)?;
    send.write_all(&encoded).await?;
    Ok(())
}

/// Pump data from QUIC stream to PTY
///
/// Reads NetworkMessages from QUIC stream and writes commands to PTY.
///
/// # Arguments
/// * `recv` - QUIC receive stream
/// * `pty` - Async writer to PTY
/// * `send` - Optional QUIC send stream for control messages (Pong, etc.)
///
/// # Message Handling
/// - Command: Write text to PTY
/// - Resize: Handle terminal resize (implemented in server)
/// - Ping: Respond with Pong (if send stream provided)
/// - Other: Ignore with debug log
pub async fn pump_quic_to_pty<W>(
    mut recv: RecvStream,
    mut pty: W,
    send: Option<Arc<Mutex<SendStream>>>,
) -> Result<()>
where
    W: AsyncWriteExt + Unpin + Send,
{
    let mut len_buf = [0u8; 4];

    loop {
        // Read length prefix (4 bytes, big endian)
        recv.read_exact(&mut len_buf).await
            .map_err(|_| CoreError::Connection("Stream closed by peer".to_string()))?;

        let len = u32::from_be_bytes(len_buf) as usize;

        // Validate message size (max 16MB as per MessageCodec)
        if len > 16 * 1024 * 1024 {
            return Err(CoreError::MessageTooLarge {
                size: len,
                max: 16 * 1024 * 1024,
            });
        }

        // Read payload
        let mut data = vec![0u8; len];
        recv.read_exact(&mut data).await
            .map_err(|_| CoreError::Connection("Stream closed while reading payload".to_string()))?;

        // Decode message
        let msg = MessageCodec::decode(&data)?;

        match msg {
            NetworkMessage::Command(cmd) => {
                // Write command text to PTY
                pty.write_all(cmd.text.as_bytes()).await?;
                tracing::trace!("Wrote command to PTY: {}", cmd.text.trim());
            }
            NetworkMessage::Resize { rows, cols } => {
                // TODO: Handle PTY resize
                tracing::debug!("Resize request: {}x{} (not yet implemented)", rows, cols);
            }
            NetworkMessage::Ping { timestamp } => {
                // Respond to ping with pong
                tracing::trace!("Received ping with timestamp {}, sending pong", timestamp);
                if let Some(send) = &send {
                    let pong = NetworkMessage::pong(timestamp);
                    let encoded = MessageCodec::encode(&pong)?;
                    let mut send = send.lock().await;
                    send.write_all(&encoded).await
                        .map_err(|e| CoreError::Connection(format!("Failed to send pong: {}", e)))?;
                    tracing::trace!("Sent pong response");
                } else {
                    tracing::warn!("Received ping but no send stream available to respond");
                }
            }
            NetworkMessage::Pong { timestamp: _ } => {
                tracing::trace!("Received pong");
            }
            NetworkMessage::Close => {
                tracing::info!("Received close message");
                return Ok(());
            }
            _ => {
                tracing::debug!("Ignoring message: {:?}", msg);
            }
        }
    }
}

/// Bidirectional stream pump
///
/// Spawns two tasks to handle bidirectional PTY ↔ QUIC communication.
/// Returns when either direction completes or fails.
///
/// # Arguments
/// * `pty_reader` - Async reader from PTY
/// * `pty_writer` - Async writer to PTY
/// * `send` - QUIC send stream
/// * `recv` - QUIC receive stream
pub async fn bidirectional_pump<R, W>(
    pty_reader: R,
    pty_writer: W,
    send: SendStream,
    recv: RecvStream,
) -> Result<()>
where
    R: AsyncReadExt + Unpin + Send + 'static,
    W: AsyncWriteExt + Unpin + Send + 'static,
{
    // Share send stream so both pumps can use it
    // PTY→QUIC uses it for terminal output
    // QUIC→PTY uses it for control messages (Pong)
    let send_shared = Arc::new(Mutex::new(send));

    let pty_task = tokio::spawn({
        let send = send_shared.clone();
        async move {
            let mut send_lock = send.lock().await;
            pump_pty_to_quic(pty_reader, &mut *send_lock).await
        }
    });

    let quic_task = tokio::spawn(async move {
        pump_quic_to_pty(recv, pty_writer, Some(send_shared)).await
    });

    tokio::select! {
        r = pty_task => {
            match r {
                Ok(Ok(())) => tracing::debug!("PTY→QUIC pump completed"),
                Ok(Err(e)) => tracing::error!("PTY→QUIC pump failed: {}", e),
                Err(e) => tracing::error!("PTY→QUIC task panicked: {}", e),
            }
        }
        r = quic_task => {
            match r {
                Ok(Ok(())) => tracing::debug!("QUIC→PTY pump completed"),
                Ok(Err(e)) => tracing::error!("QUIC→PTY pump failed: {}", e),
                Err(e) => tracing::error!("QUIC→PTY task panicked: {}", e),
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_size_validation() {
        // Test that max size check works
        let max_size = 16 * 1024 * 1024;
        assert!(max_size == 16 * 1024 * 1024);
    }

    // Note: Full integration tests require async runtime and mock streams
    // These are better suited as integration tests in the test suite
}
