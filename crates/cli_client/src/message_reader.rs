//! Message reader for length-prefixed QUIC messages
//!
//! Wraps framing logic to read complete messages from QUIC stream.
//! Protocol format: [4-byte big-endian length][N-byte payload]

use anyhow::Result;
use comacode_core::{MessageCodec, NetworkMessage};
use quinn::RecvStream;

/// Helper for reading length-prefixed messages from QUIC stream
pub struct MessageReader {
    recv: RecvStream,
}

impl MessageReader {
    /// Create new MessageReader from QUIC RecvStream
    pub fn new(recv: RecvStream) -> Self {
        Self { recv }
    }

    /// Read next complete message from stream
    /// Blocks until full message received
    pub async fn read_message(&mut self) -> Result<NetworkMessage> {
        // Read 4-byte length prefix
        let mut len_buf = [0u8; 4];
        self.recv.read_exact(&mut len_buf).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading length"))?;

        let len = u32::from_be_bytes(len_buf) as usize;

        // Validate size (prevent DoS)
        if len > 16 * 1024 * 1024 {
            return Err(anyhow::anyhow!("Message too large: {} bytes", len));
        }

        // Read payload
        let mut data = vec![0u8; len];
        self.recv.read_exact(&mut data).await
            .map_err(|_| anyhow::anyhow!("Stream closed while reading payload"))?;

        // Decode message
        MessageCodec::decode(&data)
            .map_err(|e| anyhow::anyhow!("Decode failed: {}", e))
    }
}
