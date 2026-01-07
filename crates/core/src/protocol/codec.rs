//! Postcard serialization codec for network messages

use crate::error::{CoreError, Result};
use crate::types::NetworkMessage;
use postcard::{from_bytes, to_allocvec};

/// Maximum message size (16MB)
const MAX_MESSAGE_SIZE: usize = 16 * 1024 * 1024;

/// Message codec for serialization/deserialization
pub struct MessageCodec;

impl MessageCodec {
    /// Encode network message to bytes
    ///
    /// Returns Vec<u8> with length-prefixed format:
    /// [4 bytes length (big endian)] [message payload]
    pub fn encode(msg: &NetworkMessage) -> Result<Vec<u8>> {
        let payload = to_allocvec(msg).map_err(CoreError::from)?;

        // Limit message size
        if payload.len() > MAX_MESSAGE_SIZE {
            return Err(CoreError::MessageTooLarge {
                size: payload.len(),
                max: MAX_MESSAGE_SIZE,
            });
        }

        // Add length prefix (4 bytes, big endian)
        let len = payload.len() as u32;
        let mut buf = Vec::with_capacity(4 + payload.len());
        buf.extend_from_slice(&len.to_be_bytes());
        buf.extend_from_slice(&payload);

        Ok(buf)
    }

    /// Decode network message from bytes
    ///
    /// Expects length-prefixed format
    pub fn decode(buf: &[u8]) -> Result<NetworkMessage> {
        if buf.len() < 4 {
            return Err(CoreError::InvalidMessageFormat(
                "Buffer too small for length prefix".into(),
            ));
        }

        // Read length prefix
        let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

        // Validate length
        if len > MAX_MESSAGE_SIZE {
            return Err(CoreError::MessageTooLarge {
                size: len,
                max: MAX_MESSAGE_SIZE,
            });
        }

        if buf.len() < 4 + len {
            return Err(CoreError::InvalidMessageFormat(
                "Buffer too small for payload".into(),
            ));
        }

        // Deserialize payload
        let payload = &buf[4..4 + len];
        from_bytes(payload).map_err(CoreError::from)
    }

    /// Decode slice into multiple messages (streaming)
    pub fn decode_stream(buf: &[u8]) -> Result<Vec<NetworkMessage>> {
        let mut messages = Vec::new();
        let mut offset = 0;

        while offset < buf.len() {
            if offset + 4 > buf.len() {
                break; // Incomplete message
            }

            let len = u32::from_be_bytes([
                buf[offset],
                buf[offset + 1],
                buf[offset + 2],
                buf[offset + 3],
            ]) as usize;

            if offset + 4 + len > buf.len() {
                break; // Incomplete message
            }

            let msg_buf = &buf[offset + 4..offset + 4 + len];
            let msg = from_bytes(msg_buf).map_err(CoreError::from)?;
            messages.push(msg);

            offset += 4 + len;
        }

        Ok(messages)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::TerminalCommand;

    #[test]
    fn test_encode_decode_roundtrip() {
        let msg = NetworkMessage::Close;
        let encoded = MessageCodec::encode(&msg).unwrap();
        let decoded = MessageCodec::decode(&encoded).unwrap();
        assert_eq!(msg, decoded);
    }

    #[test]
    fn test_command_message() {
        let cmd = TerminalCommand::new("echo hello".to_string());
        let msg = NetworkMessage::Command(cmd);
        let encoded = MessageCodec::encode(&msg).unwrap();
        let decoded = MessageCodec::decode(&encoded).unwrap();
        assert_eq!(msg, decoded);
    }

    #[test]
    fn test_ping_pong() {
        let ping = NetworkMessage::ping();
        let encoded = MessageCodec::encode(&ping).unwrap();
        let decoded = MessageCodec::decode(&encoded).unwrap();
        assert!(matches!(decoded, NetworkMessage::Ping { .. }));
    }

    #[test]
    fn test_stream_decode() {
        let msg1 = NetworkMessage::Close;
        let msg2 = NetworkMessage::ping();

        let enc1 = MessageCodec::encode(&msg1).unwrap();
        let enc2 = MessageCodec::encode(&msg2).unwrap();

        let mut stream = Vec::new();
        stream.extend_from_slice(&enc1);
        stream.extend_from_slice(&enc2);

        let messages = MessageCodec::decode_stream(&stream).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0], msg1);
        assert!(matches!(messages[1], NetworkMessage::Ping { .. }));
    }

    #[test]
    fn test_invalid_buffer() {
        let result = MessageCodec::decode(&[1, 2, 3]);
        assert!(result.is_err());
    }
}
