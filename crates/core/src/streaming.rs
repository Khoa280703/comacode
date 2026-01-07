//! Channel-based output streaming with zero-copy bytes
//!
//! This module provides a bounded channel-based architecture for terminal output
//! streaming, eliminating race conditions from shared state and creating natural
//! backpressure.

use bytes::Bytes;
use tokio::sync::mpsc;

/// Bounded channel for terminal output streaming
///
/// Uses `Bytes` instead of `Vec<u8>` for zero-copy cloning.
/// Channel capacity creates natural backpressure when buffer fills.
pub struct OutputStream {
    tx: mpsc::Sender<Bytes>,
}

impl OutputStream {
    /// Create new stream with specified buffer capacity
    ///
    /// # Arguments
    /// * `capacity` - Maximum number of messages in channel buffer
    ///
    /// # Returns
    /// * `(OutputStream, mpsc::Receiver<Bytes>)` - Sender and receiver halves
    pub fn new(capacity: usize) -> (Self, mpsc::Receiver<Bytes>) {
        let (tx, rx) = mpsc::channel(capacity);
        (Self { tx }, rx)
    }

    /// Send PTY output asynchronously
    ///
    /// Returns error if buffer full (backpressure) or receiver dropped.
    pub async fn send(&self, data: Bytes) -> Result<(), mpsc::error::SendError<Bytes>> {
        self.tx.send(data).await
    }

    /// Try send without waiting (non-blocking)
    ///
    /// Returns immediately with error if buffer full.
    pub fn try_send(&self, data: Bytes) -> Result<(), mpsc::error::TrySendError<Bytes>> {
        self.tx.try_send(data)
    }

    /// Get current channel capacity (for monitoring)
    #[inline]
    pub fn capacity(&self) -> usize {
        self.tx.capacity()
    }

    /// Get approximate remaining slots in buffer
    ///
    /// Useful for backpressure monitoring and logging.
    /// Note: This is an approximation based on channel capacity.
    #[inline]
    pub fn remaining(&self) -> usize {
        // Tokio mpsc doesn't expose remaining count directly
        // Return capacity as approximation (conservative estimate)
        self.capacity()
    }

    /// Get sender for cloning (needed for spawn_blocking)
    ///
    /// # Note
    /// Cloning sender is cheap (Arc-based), allows multiple producers.
    pub fn sender(&self) -> mpsc::Sender<Bytes> {
        self.tx.clone()
    }

    /// Check if channel is closed
    #[inline]
    pub fn is_closed(&self) -> bool {
        self.tx.is_closed()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{timeout, Duration};

    #[tokio::test]
    async fn test_basic_send_receive() {
        let (stream, mut rx) = OutputStream::new(10);

        let data = Bytes::from("hello");
        stream.send(data.clone()).await.unwrap();

        let received = rx.recv().await.unwrap();
        assert_eq!(data, received);
    }

    #[tokio::test]
    async fn test_backpressure_blocking() {
        let (stream, mut rx) = OutputStream::new(2); // Small buffer

        // Fill buffer
        stream.send(Bytes::from("msg1")).await.unwrap();
        stream.send(Bytes::from("msg2")).await.unwrap();

        // This send should block until we drain
        let send_task = tokio::spawn(async move {
            stream.send(Bytes::from("msg3")).await.unwrap();
        });

        // Verify send doesn't complete immediately (would timeout if blocking)
        let result = timeout(Duration::from_millis(100), send_task).await;
        assert!(result.is_err(), "Send should block when buffer full");

        // Drain one message
        rx.recv().await.unwrap();

        // Now send should complete
        let _ = timeout(Duration::from_millis(100), rx.recv()).await.unwrap();
    }

    #[tokio::test]
    async fn test_try_send_fails_when_full() {
        let (stream, _rx) = OutputStream::new(2);

        stream.try_send(Bytes::from("msg1")).unwrap();
        stream.try_send(Bytes::from("msg2")).unwrap();

        // Should fail immediately
        let result = stream.try_send(Bytes::from("msg3"));
        assert!(result.is_err(), "try_send should fail when buffer full");
    }

    #[tokio::test]
    async fn test_remaining_capacity() {
        let (stream, _rx) = OutputStream::new(10);

        assert_eq!(stream.remaining(), 10);

        stream.send(Bytes::from("msg1")).await.unwrap();
        assert_eq!(stream.remaining(), 9);

        stream.send(Bytes::from("msg2")).await.unwrap();
        assert_eq!(stream.remaining(), 8);
    }

    #[tokio::test]
    async fn test_bytes_zero_copy() {
        let (stream, mut rx) = OutputStream::new(10);

        let data = Bytes::from(vec![1u8, 2, 3, 4, 5]);

        // Clone is cheap (just ref count increment)
        stream.send(data.clone()).await.unwrap();
        stream.send(data.clone()).await.unwrap();

        // Both clones should be identical
        let recv1 = rx.recv().await.unwrap();
        let recv2 = rx.recv().await.unwrap();

        assert_eq!(recv1, data);
        assert_eq!(recv2, data);
        assert_eq!(recv1.as_ptr(), recv2.as_ptr(), "Same underlying memory");
    }

    #[tokio::test]
    async fn test_channel_close_detection() {
        let (stream, rx) = OutputStream::new(10);

        assert!(!stream.is_closed());

        // Drop receiver
        drop(rx);

        // Give time for close to propagate
        tokio::task::yield_now().await;

        // Sender should detect closed channel
        assert!(stream.is_closed());

        // Send should fail
        let result = stream.send(Bytes::from("msg")).await;
        assert!(result.is_err());
    }
}
