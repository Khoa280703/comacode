//! Flutter Rust Bridge API
//!
//! FFI-safe functions for Dart integration

use comacode_core::{TerminalCommand, NetworkMessage, MessageCodec};
use flutter_rust_bridge::frb;

/// Create a new terminal command
#[frb(sync)]
pub fn create_command(text: String) -> TerminalCommand {
    TerminalCommand::new(text)
}

/// Get command ID
#[frb(sync)]
pub fn get_command_id(cmd: &TerminalCommand) -> u64 {
    cmd.id
}

/// Get command text
#[frb(sync)]
pub fn get_command_text(cmd: &TerminalCommand) -> String {
    cmd.text.clone()
}

/// Get command timestamp
#[frb(sync)]
pub fn get_command_timestamp(cmd: &TerminalCommand) -> u64 {
    cmd.timestamp
}

/// Encode terminal command to bytes for network transmission
#[frb]
pub async fn encode_command(cmd: TerminalCommand) -> Result<Vec<u8>, String> {
    MessageCodec::encode(&NetworkMessage::Command(cmd))
        .map_err(|e| e.to_string())
}

/// Encode ping message
#[frb]
pub async fn encode_ping() -> Result<Vec<u8>, String> {
    MessageCodec::encode(&NetworkMessage::ping())
        .map_err(|e| e.to_string())
}

/// Encode resize message
#[frb]
pub async fn encode_resize(rows: u16, cols: u16) -> Result<Vec<u8>, String> {
    MessageCodec::encode(&NetworkMessage::resize(rows, cols))
        .map_err(|e| e.to_string())
}

/// Decode network message from bytes
#[frb]
pub async fn decode_message(data: Vec<u8>) -> Result<String, String> {
    let msg = MessageCodec::decode(&data)
        .map_err(|e| e.to_string())?;

    // Return debug representation for now
    // In production, you'd return a proper Dart-compatible type
    Ok(format!("{:?}", msg))
}

/// Terminal configuration for Flutter
#[frb(sync)]
pub struct TerminalConfig {
    pub rows: u16,
    pub cols: u16,
    pub shell: String,
}

impl Default for TerminalConfig {
    fn default() -> Self {
        Self {
            rows: 24,
            cols: 80,
            shell: "/bin/bash".to_string(),
        }
    }
}

/// Create terminal config with custom size
#[frb(sync)]
pub fn create_terminal_config(rows: u16, cols: u16) -> TerminalConfig {
    TerminalConfig {
        rows,
        cols,
        ..Default::default()
    }
}

/// Simple add function for testing FFI
#[frb(sync)]
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

/// Greeting function for testing FFI
#[frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {}!", name)
}
