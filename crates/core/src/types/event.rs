//! Terminal event types for host output

use serde::{Deserialize, Serialize};

/// Terminal event sent from host to mobile
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TerminalEvent {
    /// Terminal output data (UTF-8 bytes)
    Output { data: Vec<u8> },

    /// Terminal error message
    Error { message: String },

    /// Terminal process exited
    Exit { code: i32 },

    /// Terminal resize acknowledgement
    Resized { rows: u16, cols: u16 },
}

impl TerminalEvent {
    /// Create output event from bytes
    pub fn output(data: Vec<u8>) -> Self {
        Self::Output { data }
    }

    /// Create output event from string (UTF-8)
    pub fn output_str(s: &str) -> Self {
        Self::Output {
            data: s.as_bytes().to_vec(),
        }
    }

    /// Create error event
    pub fn error(message: String) -> Self {
        Self::Error { message }
    }

    /// Create exit event
    pub fn exit(code: i32) -> Self {
        Self::Exit { code }
    }

    /// Create resized event
    pub fn resized(rows: u16, cols: u16) -> Self {
        Self::Resized { rows, cols }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_output() {
        let event = TerminalEvent::output_str("Hello, World!");
        assert_eq!(event, TerminalEvent::Output {
            data: b"Hello, World!".to_vec()
        });
    }

    #[test]
    fn test_event_serialization() {
        let event = TerminalEvent::exit(0);
        let serialized = postcard::to_allocvec(&event).unwrap();
        let deserialized: TerminalEvent = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(event, deserialized);
    }
}
