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

    // ===== Multi-Session Events - Phase 04 =====

    /// Session created successfully
    SessionCreated { session_id: String },

    /// Session exists and can be re-attached
    SessionReAttach { session_id: String },

    /// Session not found (need to re-spawn)
    SessionNotFound { session_id: String },

    /// Active session switched
    SessionSwitched { session_id: String },

    /// Session closed successfully
    SessionClosed { session_id: String },
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

    // ===== Session event helpers - Phase 04 =====

    /// Create session created event
    pub fn session_created(session_id: String) -> Self {
        Self::SessionCreated { session_id }
    }

    /// Create session re-attach event
    pub fn session_reattach(session_id: String) -> Self {
        Self::SessionReAttach { session_id }
    }

    /// Create session not found event
    pub fn session_not_found(session_id: String) -> Self {
        Self::SessionNotFound { session_id }
    }

    /// Create session switched event
    pub fn session_switched(session_id: String) -> Self {
        Self::SessionSwitched { session_id }
    }

    /// Create session closed event
    pub fn session_closed(session_id: String) -> Self {
        Self::SessionClosed { session_id }
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
