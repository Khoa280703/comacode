//! Terminal command types for mobile input

use serde::{Deserialize, Serialize};

/// Terminal command sent from mobile to host
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TerminalCommand {
    /// Unique command ID
    pub id: u64,
    /// Command text or keystroke input
    pub text: String,
    /// Unix timestamp (milliseconds)
    pub timestamp: u64,
}

impl TerminalCommand {
    /// Create new terminal command
    pub fn new(text: String) -> Self {
        Self {
            id: Self::generate_id(),
            text,
            timestamp: Self::now(),
        }
    }

    fn generate_id() -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_micros() as u64)
            .unwrap_or(0)
    }

    fn now() -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_creation() {
        let cmd = TerminalCommand::new("ls -la".to_string());
        assert_eq!(cmd.text, "ls -la");
        assert!(cmd.id > 0);
        assert!(cmd.timestamp > 0);
    }

    #[test]
    fn test_command_serialization() {
        let cmd = TerminalCommand::new("echo test".to_string());
        let serialized = postcard::to_allocvec(&cmd).unwrap();
        let deserialized: TerminalCommand = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(cmd, deserialized);
    }
}
