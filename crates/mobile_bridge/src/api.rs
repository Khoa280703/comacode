//! Flutter Rust Bridge API
//!
//! FFI-safe functions for Dart integration
//!
//! Phase 04: Added QUIC client support
//! Phase 04.1: Fixed UB - replaced static mut with once_cell::sync::OnceCell
//! Phase 04.2: Use RwLock<Option<>> for reconnect support
//! Phase VFS-1: Directory listing API
//! Phase VFS-3: File watcher API

use comacode_core::{NetworkMessage, MessageCodec};
use comacode_core::types::FileEventType;
use flutter_rust_bridge::frb;
use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::sync::Mutex;
use crate::quic_client::QuicClient;

// Re-export commonly used types for FRB
// These are both imported and re-exported for FRB generated code visibility
pub use comacode_core::{TerminalCommand, TerminalEvent, QrPayload};
pub use comacode_core::types::DirEntry;

/// CryptoProvider initializer (rustls 0.23+ requires runtime init)
///
/// Using OnceCell ensures ring crypto provider is installed exactly once
/// before any QUIC connection is attempted.
static CRYPTO_INIT: OnceCell<()> = OnceCell::new();

/// Initialize the CryptoProvider with ring backend
///
/// This must be called before any rustls operations.
/// Safe to call multiple times - OnceCell ensures it only runs once.
fn init_crypto_provider() {
    CRYPTO_INIT.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Global client instance (thread-safe, reconnectable)
///
/// Using OnceCell<RwLock<Option<>>> allows:
/// - Lazy initialization on first use
/// - Reconnection after failure
/// - Explicit disconnect and reconnect
/// - Thread-safe access in async context
static QUIC_CLIENT: OnceCell<tokio::sync::RwLock<Option<Arc<Mutex<QuicClient>>>>> = OnceCell::new();

/// Connect to remote host
///
/// This is the main FFI entry point for Flutter app.
/// Call this after scanning QR code to get connection parameters.
///
/// # Arguments
/// * `host` - Server IP address
/// * `port` - QUIC server port
/// * `auth_token` - Authentication token from QR scan
/// * `fingerprint` - Certificate fingerprint for TOFU verification
///
/// # Behavior
/// - If already connected: Returns error (call disconnect first)
/// - On success: Stores client for subsequent operations
#[frb]
pub async fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
) -> Result<(), String> {
    // Initialize rustls CryptoProvider first (required for rustls 0.23+)
    init_crypto_provider();

    // Get or init the RwLock
    let lock = QUIC_CLIENT.get_or_init(|| tokio::sync::RwLock::new(None));

    // Check if already connected (read lock)
    {
        let client_guard = lock.read().await;
        if client_guard.is_some() {
            return Err(
                "Already connected. Disconnect first to reconnect.".to_string()
            );
        }
    }

    // Create new client
    let client = Arc::new(Mutex::new(QuicClient::new(fingerprint)));

    // Connect
    {
        let mut client_lock = client.lock().await;
        client_lock.connect(host, port, auth_token).await?;
    }

    // Store client (write lock)
    {
        let mut client_guard = lock.write().await;
        *client_guard = Some(client);
    }

    Ok(())
}

/// Receive next terminal event from server
///
/// Call this in a loop to stream terminal output.
/// Returns when a new event is available.
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn receive_terminal_event() -> Result<TerminalEvent, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.receive_event().await
}

/// Send command to remote terminal
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn send_terminal_command(command: String) -> Result<(), String> {
    tracing::info!("🔵 [FRB] Sending command: '{}'", command);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    let result = client.send_command(command).await;
    match &result {
        Ok(()) => tracing::info!("✅ [FRB] Command sent successfully"),
        Err(e) => tracing::error!("❌ [FRB] Command send failed: {}", e),
    }
    result
}

/// Send raw input bytes to remote terminal (pure passthrough)
///
/// Phase 08: Send raw keystrokes directly to PTY without String conversion.
/// Use this for proper Ctrl+C, backspace, and other control characters.
///
/// # Arguments
/// * `data` - Raw bytes from stdin (including control chars like 0x03 for Ctrl+C)
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn send_raw_input(data: Vec<u8>) -> Result<(), String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.send_raw_input(data).await
}

/// Resize PTY (for screen rotation support)
///
/// Phase 06: Send resize event to update PTY size on server.
/// Call this when device orientation changes.
///
/// # Arguments
/// * `rows` - Number of rows (characters per column)
/// * `cols` - Number of columns (characters per row)
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn resize_pty(rows: u16, cols: u16) -> Result<(), String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.resize_pty(rows, cols).await
}

/// Disconnect from host
///
/// Clears the client, allowing reconnect.
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn disconnect_from_host() -> Result<(), String> {
    // Get and clear client (write lock)
    let client_arc = {
        let lock = QUIC_CLIENT.get_or_init(|| tokio::sync::RwLock::new(None));
        let mut client_guard = lock.write().await;
        client_guard.take()
            .ok_or_else(|| "Not connected".to_string())?
    };

    // Disconnect (outside lock to avoid deadlock)
    let mut client = client_arc.lock().await;
    client.disconnect().await
}

/// Check if connected
///
/// Returns false if client not initialized or disconnected.
#[frb]
pub async fn is_connected() -> bool {
    let lock = QUIC_CLIENT.get_or_init(|| tokio::sync::RwLock::new(None));
    let client_guard = lock.read().await;

    if let Some(client_arc) = client_guard.as_ref() {
        let client = client_arc.lock().await;
        client.is_connected().await
    } else {
        false
    }
}

/// Helper: Get client reference
///
/// Returns error if not connected.
async fn get_client() -> Result<Arc<Mutex<QuicClient>>, String> {
    let lock = QUIC_CLIENT.get_or_init(|| tokio::sync::RwLock::new(None));
    lock.read()
        .await
        .as_ref()
        .cloned()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())
}

// ===== Existing encode/decode functions =====

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

/// Encode raw input bytes for network transmission (pure passthrough)
///
/// Phase 08: Encode raw keystrokes without String conversion.
/// Use this for proper Ctrl+C, backspace, and other control characters.
#[frb]
pub async fn encode_input(data: Vec<u8>) -> Result<Vec<u8>, String> {
    MessageCodec::encode(&NetworkMessage::Input { data })
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

// ===== QR Payload functions =====

/// Parse QR payload JSON string
#[frb]
pub fn parse_qr_payload(json: String) -> Result<QrPayload, String> {
    QrPayload::from_json(&json).map_err(|e| e.to_string())
}

/// Get QR payload fields
#[frb(sync)]
pub fn get_qr_ip(payload: &QrPayload) -> String {
    payload.ip.clone()
}

#[frb(sync)]
pub fn get_qr_port(payload: &QrPayload) -> u16 {
    payload.port
}

#[frb(sync)]
pub fn get_qr_fingerprint(payload: &QrPayload) -> String {
    payload.fingerprint.clone()
}

#[frb(sync)]
pub fn get_qr_token(payload: &QrPayload) -> String {
    payload.token.clone()
}

#[frb(sync)]
pub fn get_qr_protocol_version(payload: &QrPayload) -> u32 {
    payload.protocol_version
}

// ===== Terminal Event functions =====

/// Create output event from bytes
#[frb(sync)]
pub fn event_output(data: Vec<u8>) -> TerminalEvent {
    TerminalEvent::output(data)
}

/// Create output event from string
#[frb(sync)]
pub fn event_output_str(s: String) -> TerminalEvent {
    TerminalEvent::output_str(&s)
}

/// Get event data (for Output events)
#[frb(sync)]
pub fn get_event_data(event: &TerminalEvent) -> Vec<u8> {
    match event {
        TerminalEvent::Output { data } => data.clone(),
        _ => Vec::new(),
    }
}

/// Get event error message (for Error events)
#[frb(sync)]
pub fn get_event_error_message(event: &TerminalEvent) -> String {
    match event {
        TerminalEvent::Error { message } => message.clone(),
        _ => String::new(),
    }
}

/// Get event exit code (for Exit events)
#[frb(sync)]
pub fn get_event_exit_code(event: &TerminalEvent) -> i32 {
    match event {
        TerminalEvent::Exit { code } => *code,
        _ => -1,
    }
}

/// Check if event is Output
#[frb(sync)]
pub fn is_event_output(event: &TerminalEvent) -> bool {
    matches!(event, TerminalEvent::Output { .. })
}

/// Check if event is Error
#[frb(sync)]
pub fn is_event_error(event: &TerminalEvent) -> bool {
    matches!(event, TerminalEvent::Error { .. })
}

/// Check if event is Exit
#[frb(sync)]
pub fn is_event_exit(event: &TerminalEvent) -> bool {
    matches!(event, TerminalEvent::Exit { .. })
}

// ===== VFS (Virtual File System) Functions - Phase 1 =====

/// Request directory listing from server
///
/// Sends ListDir message. Server responds with multiple DirChunk messages.
/// Call receive_dir_chunk() in a loop to receive all chunks.
///
/// # Arguments
/// * `path` - Absolute path to list (e.g., "/tmp", "/home/user")
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn request_list_dir(path: String) -> Result<(), String> {
    tracing::info!("📁 [FRB] request_list_dir: {}", path);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.request_list_dir(path).await
}

/// Receive next directory chunk from server (NON-BLOCKING)
///
/// Returns a chunk with entries. Call repeatedly until has_more is false.
/// Returns None if no chunks available yet (server still processing).
///
/// # Returns
/// * `Some((chunk_index, entries, has_more))` - Chunk received
/// * `None` - No chunks available yet
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn receive_dir_chunk() -> Result<Option<(u32, Vec<DirEntry>, bool)>, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.receive_dir_chunk().await
}

// ===== DirEntry helper functions for Dart =====

/// Get entry name
#[frb(sync)]
pub fn get_dir_entry_name(entry: &DirEntry) -> String {
    entry.name.clone()
}

/// Get entry path
#[frb(sync)]
pub fn get_dir_entry_path(entry: &DirEntry) -> String {
    entry.path.clone()
}

/// Check if entry is a directory
#[frb(sync)]
pub fn is_dir_entry_dir(entry: &DirEntry) -> bool {
    entry.is_dir
}

/// Check if entry is a symlink
#[frb(sync)]
pub fn is_dir_entry_symlink(entry: &DirEntry) -> bool {
    entry.is_symlink
}

/// Get entry size (bytes)
#[frb(sync)]
pub fn get_dir_entry_size(entry: &DirEntry) -> Option<u64> {
    entry.size
}

/// Get entry modified timestamp (Unix epoch seconds)
#[frb(sync)]
pub fn get_dir_entry_modified(entry: &DirEntry) -> Option<u64> {
    entry.modified
}

/// Get entry permissions string
#[frb(sync)]
pub fn get_dir_entry_permissions(entry: &DirEntry) -> Option<String> {
    entry.permissions.clone()
}

// ===== VFS File Watcher Functions - Phase 3 =====

/// Request server to watch a directory for changes
///
/// Server will push FileEvent messages when files are created/modified/deleted.
/// Call receive_file_event() in a loop to receive watcher events.
///
/// # Arguments
/// * `path` - Absolute path to watch (e.g., "/tmp", "/home/user/project")
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn request_watch_dir(path: String) -> Result<(), String> {
    tracing::info!("📁 [FRB] request_watch_dir: {}", path);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.request_watch_dir(path).await
}

/// Request server to stop watching a directory
///
/// # Arguments
/// * `watcher_id` - ID of the watcher to stop (returned in WatchStarted event)
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn request_unwatch_dir(watcher_id: String) -> Result<(), String> {
    tracing::info!("📁 [FRB] request_unwatch_dir: {}", watcher_id);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.request_unwatch_dir(watcher_id).await
}

/// File watcher event data (for Dart)
#[derive(Debug, Clone)]
#[frb(sync)]
pub struct FileWatcherEventData {
    /// Event type: "file", "started", or "error"
    pub event_type: String,
    /// Watcher ID (for started/error events)
    pub watcher_id: String,
    /// File path (for file events)
    pub path: String,
    /// File event type: "created", "modified", "deleted", "renamed"
    pub file_event_type: String,
    /// Old name (for rename events only)
    pub old_name: String,
    /// Event timestamp (Unix epoch seconds)
    pub timestamp: u64,
    /// Error message (for error events only)
    pub error: String,
}

impl Default for FileWatcherEventData {
    fn default() -> Self {
        Self {
            event_type: String::new(),
            watcher_id: String::new(),
            path: String::new(),
            file_event_type: String::new(),
            old_name: String::new(),
            timestamp: 0,
            error: String::new(),
        }
    }
}

/// Receive next file watcher event from server (NON-BLOCKING)
///
/// Returns watcher events (FileEvent, WatchStarted, WatchError).
/// Call repeatedly in a loop to process all events.
/// Returns None if no events available yet.
///
/// # Returns
/// * `Some(FileWatcherEventData)` - Event received
/// * `None` - No events available yet
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn receive_file_event() -> Result<Option<FileWatcherEventData>, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;

    match client.receive_file_event().await? {
        Some(event) => {
            let data = match event {
                crate::quic_client::FileWatcherEventData::FileEvent(e) => FileWatcherEventData {
                    event_type: "file".to_string(),
                    watcher_id: e.watcher_id,
                    path: e.path,
                    file_event_type: match e.event_type {
                        FileEventType::Created => "created".to_string(),
                        FileEventType::Modified => "modified".to_string(),
                        FileEventType::Deleted => "deleted".to_string(),
                        FileEventType::Renamed { ref old_name } => {
                            format!("renamed:{}", old_name)
                        }
                    },
                    old_name: match &e.event_type {
                        FileEventType::Renamed { old_name } => old_name.clone(),
                        _ => String::new(),
                    },
                    timestamp: e.timestamp,
                    error: String::new(),
                },
                crate::quic_client::FileWatcherEventData::Started(e) => FileWatcherEventData {
                    event_type: "started".to_string(),
                    watcher_id: e.watcher_id,
                    ..Default::default()
                },
                crate::quic_client::FileWatcherEventData::Error(e) => FileWatcherEventData {
                    event_type: "error".to_string(),
                    watcher_id: e.watcher_id,
                    error: e.error,
                    ..Default::default()
                },
            };
            Ok(Some(data))
        }
        None => Ok(None),
    }
}

/// Get file event buffer length (for monitoring)
///
/// Returns number of buffered events waiting to be processed.
#[frb]
pub async fn file_event_buffer_len() -> Result<usize, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    Ok(client.file_event_buffer_len().await)
}

// ===== Test functions =====

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
