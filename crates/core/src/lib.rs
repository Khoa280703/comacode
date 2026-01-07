//! Comacode Core - Shared business logic for terminal control
//!
//! This crate provides:
//! - Domain types (commands, events, messages)
//! - Protocol handling (Postcard serialization)
//! - Terminal abstraction trait
//! - Error types
//! - Authentication types (Phase E03)

// Version constants
pub const PROTOCOL_VERSION: u32 = 1;
pub const APP_VERSION_STRING: &str = "0.1.0-mvp";
pub const SNAPSHOT_BUFFER_LINES: usize = 1000;

pub mod auth;
pub mod error;
pub mod protocol;
pub mod streaming;
pub mod terminal;
pub mod types;

// Re-export common types
pub use auth::AuthToken;
pub use error::{CoreError, Result};
pub use protocol::MessageCodec;
pub use streaming::OutputStream;
pub use terminal::{Terminal, TerminalConfig, MockTerminal};
pub use types::{NetworkMessage, TerminalCommand, TerminalEvent, QrPayload};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_constants_defined() {
        assert_eq!(PROTOCOL_VERSION, 1);
        assert!(APP_VERSION_STRING.starts_with("0.1.0"));
    }
}
