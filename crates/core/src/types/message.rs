//! Network protocol messages

use serde::{Deserialize, Serialize};
use crate::{AuthToken, CoreError, PROTOCOL_VERSION, APP_VERSION_STRING, Result};
use super::{TerminalCommand, TerminalEvent};

/// Network message type for QUIC protocol
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum NetworkMessage {
    /// Protocol handshake
    /// Phase E03: auth_token is Option<AuthToken> for authentication
    Hello {
        protocol_version: u32,  // MUST match PROTOCOL_VERSION
        app_version: String,     // For logging only
        capabilities: u32,
        auth_token: Option<AuthToken>,  // Phase E03: Token for authentication
    },

    /// Terminal command from client
    Command(TerminalCommand),

    /// Raw input bytes for pure passthrough (Phase 08+)
    /// Client sends raw keystrokes, server writes directly to PTY
    /// PTY handles echo & signal generation (Ctrl+C = SIGINT)
    /// This avoids String conversion overhead and preserves control bytes
    Input {
        /// Raw bytes from stdin (including control chars like 0x03 for Ctrl+C)
        data: Vec<u8>,
    },

    /// Terminal event from host
    Event(TerminalEvent),

    /// Heartbeat/ping
    Ping { timestamp: u64 },

    /// Pong response
    Pong { timestamp: u64 },

    /// Resize terminal request
    Resize { rows: u16, cols: u16 },

    /// Explicit PTY allocation request (SSH-like protocol)
    /// Client sends this after Hello to allocate PTY with correct size
    RequestPty {
        rows: u16,
        cols: u16,
        /// Optional: override default shell
        shell: Option<String>,
        /// Optional: additional env vars
        env: Vec<(String, String)>,
    },

    /// Explicit shell start command (SSH-like protocol)
    /// Client sends this after RequestPty to start the shell
    StartShell,

    /// Request full terminal snapshot (client → host)
    RequestSnapshot,

    /// Full terminal snapshot response (host → client)
    /// Dùng Vec<u8> để an toàn với binary data, ANSI codes, invalid UTF-8
    Snapshot {
        /// Raw terminal data (scrollback + screen gom lại)
        data: Vec<u8>,
        /// Terminal size khi snapshot
        rows: u16,
        cols: u16,
    },

    /// Connection close
    Close,

    // ===== VFS (Virtual File System) Messages - Phase 1 =====

    /// Request directory listing
    ListDir {
        path: String,
        depth: Option<u32>,  // Reserved for future recursive listing
    },

    /// Directory entry (part of DirChunk response)
    DirChunk {
        chunk_index: u32,
        total_chunks: u32,
        entries: Vec<DirEntry>,
        has_more: bool,
    },

    // ===== VFS File Watcher - Phase 3 =====

    /// Request to watch a directory for changes
    WatchDir {
        path: String,
    },

    /// Watch started successfully
    WatchStarted {
        watcher_id: String,
    },

    /// File system event
    FileEvent {
        watcher_id: String,
        path: String,
        event_type: FileEventType,
        timestamp: u64,
    },

    /// Request to stop watching
    UnwatchDir {
        watcher_id: String,
    },

    /// Watch error occurred
    WatchError {
        watcher_id: String,
        error: String,
    },

    // ===== VFS File Reading - Phase 2 =====

    /// Request to read file content
    ReadFile {
        path: String,
        max_size: usize,  // Maximum file size in bytes
    },

    /// File content response
    FileContent {
        path: String,
        content: String,
        size: usize,
        truncated: bool,  // True if file was larger than max_size
    },
}

/// Directory entry for VFS browsing
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: Option<u64>,
    pub modified: Option<u64>,
    pub permissions: Option<String>,
}

/// File system event type for watcher
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FileEventType {
    Created,
    Modified,
    Deleted,
    Renamed { old_name: String },
}

impl NetworkMessage {
    /// Create hello message
    /// Phase E03: Takes optional auth token
    pub fn hello(token: Option<AuthToken>) -> Self {
        Self::Hello {
            protocol_version: PROTOCOL_VERSION,
            app_version: APP_VERSION_STRING.to_string(),
            capabilities: 0,
            auth_token: token,
        }
    }

    /// Validate handshake message
    pub fn validate_handshake(&self) -> Result<()> {
        match self {
            NetworkMessage::Hello { protocol_version, .. } => {
                if *protocol_version == PROTOCOL_VERSION {
                    Ok(())
                } else {
                    Err(CoreError::ProtocolVersionMismatch {
                        expected: PROTOCOL_VERSION,
                        got: *protocol_version,
                    })
                }
            }
            _ => Err(CoreError::InvalidHandshake),
        }
    }

    /// Create ping message
    pub fn ping() -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Self::Ping { timestamp }
    }

    /// Create pong response
    pub fn pong(timestamp: u64) -> Self {
        Self::Pong { timestamp }
    }

    /// Create resize message
    pub fn resize(rows: u16, cols: u16) -> Self {
        Self::Resize { rows, cols }
    }

    /// Create RequestPty message (SSH-like explicit PTY allocation)
    pub fn request_pty(rows: u16, cols: u16) -> Self {
        Self::RequestPty {
            rows,
            cols,
            shell: None,
            env: vec![],
        }
    }

    /// Create RequestPty message with custom shell and env vars
    pub fn request_pty_with_config(rows: u16, cols: u16, shell: Option<String>, env: Vec<(String, String)>) -> Self {
        Self::RequestPty {
            rows,
            cols,
            shell,
            env,
        }
    }

    /// Create StartShell message (SSH-like explicit shell start)
    pub fn start_shell() -> Self {
        Self::StartShell
    }

    /// Create request snapshot message
    pub fn request_snapshot() -> Self {
        Self::RequestSnapshot
    }

    /// Create snapshot message
    pub fn snapshot(data: Vec<u8>, rows: u16, cols: u16) -> Self {
        Self::Snapshot { data, rows, cols }
    }

    /// Create ReadFile message
    pub fn read_file(path: String, max_size: usize) -> Self {
        Self::ReadFile { path, max_size }
    }

    /// Create FileContent response
    pub fn file_content(path: String, content: String, size: usize, truncated: bool) -> Self {
        Self::FileContent { path, content, size, truncated }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_creation() {
        let msg = NetworkMessage::hello(None);
        assert!(matches!(msg, NetworkMessage::Hello { .. }));
    }

    #[test]
    fn test_message_with_token() {
        let token = AuthToken::generate();
        let msg = NetworkMessage::hello(Some(token));
        assert!(matches!(msg, NetworkMessage::Hello { .. }));
    }

    #[test]
    fn test_message_serialization() {
        let msg = NetworkMessage::Close;
        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_command_message_roundtrip() {
        let cmd = TerminalCommand::new("test".to_string());
        let msg = NetworkMessage::Command(cmd.clone());
        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_handshake_validation_valid() {
        let msg = NetworkMessage::hello(None);
        assert!(msg.validate_handshake().is_ok());
    }

    #[test]
    fn test_handshake_validation_invalid_version() {
        let msg = NetworkMessage::Hello {
            protocol_version: 999,
            app_version: "0.0.0".to_string(),
            capabilities: 0,
            auth_token: None,
        };
        let result = msg.validate_handshake();
        assert!(result.is_err());
        match result.unwrap_err() {
            CoreError::ProtocolVersionMismatch { expected, got } => {
                assert_eq!(expected, 1);
                assert_eq!(got, 999);
            }
            _ => panic!("Expected ProtocolVersionMismatch error"),
        }
    }

    #[test]
    fn test_handshake_validation_invalid_message_type() {
        let msg = NetworkMessage::Ping { timestamp: 0 };
        let result = msg.validate_handshake();
        assert!(matches!(result.unwrap_err(), CoreError::InvalidHandshake));
    }

    #[test]
    fn test_snapshot_messages() {
        let data = vec![1, 2, 3, 4];
        let msg = NetworkMessage::snapshot(data.clone(), 24, 80);

        assert!(matches!(msg, NetworkMessage::Snapshot { .. }));

        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_request_snapshot() {
        let msg = NetworkMessage::request_snapshot();
        assert!(matches!(msg, NetworkMessage::RequestSnapshot));
    }

    #[test]
    fn test_hello_with_auth_token_serialization() {
        let token = AuthToken::generate();
        let msg = NetworkMessage::hello(Some(token));

        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_request_pty_message() {
        let msg = NetworkMessage::request_pty(24, 80);
        assert!(matches!(msg, NetworkMessage::RequestPty { .. }));

        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_request_pty_with_config_message() {
        let shell = Some("/bin/bash".to_string());
        let env = vec![("TERM".to_string(), "xterm-256color".to_string())];
        let msg = NetworkMessage::request_pty_with_config(24, 80, shell, env);

        assert!(matches!(msg, NetworkMessage::RequestPty { rows: 24, cols: 80, .. }));

        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }

    #[test]
    fn test_start_shell_message() {
        let msg = NetworkMessage::start_shell();
        assert!(matches!(msg, NetworkMessage::StartShell));

        let serialized = postcard::to_allocvec(&msg).unwrap();
        let deserialized: NetworkMessage = postcard::from_bytes(&serialized).unwrap();
        assert_eq!(msg, deserialized);
    }
}
