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
        if let Some(client_arc) = client_guard.as_ref() {
            let client = client_arc.lock().await;
            if client.is_connected().await {
                return Err(
                    "Already connected. Disconnect first to reconnect.".to_string()
                );
            }
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

// ===== VFS Directory Listing =====

/// List directory entries using Future API
///
/// Phase VFS-Fix: Refactored from Stream to Future for reliability.
/// Stream API had race condition where onDone fired before onData.
/// Future API is deterministic - data is returned when complete.
///
/// # Arguments
/// * `path` - Directory path to list
///
/// # Returns
/// * `Ok(Vec<DirEntry>)` - All entries in directory
/// * `Err(String)` - Error message
#[frb]
pub async fn list_directory(path: String) -> Result<Vec<DirEntry>, String> {
    use std::time::Duration;

    tracing::info!("📁 [list_directory] STARTING for path '{}'", path);

    // Get client
    let client_arc = get_client().await.map_err(|e| e.to_string())?;
    let client = client_arc.lock().await;

    // Request listing
    tracing::info!("📤 [list_directory] Sending request for '{}'", path);
    client.request_list_dir(path.clone()).await?;
    tracing::info!("✅ [list_directory] Request sent, now polling...");

    // Collect all chunks
    let mut all_entries = Vec::new();
    let mut attempts = 0;
    const MAX_ATTEMPTS: usize = 150; // 3 seconds at 20ms
    const POLL_INTERVAL: Duration = Duration::from_millis(20);
    let mut chunk_count = 0;

    loop {
        tokio::time::sleep(POLL_INTERVAL).await;

        let chunk_result = client.receive_dir_chunk().await?;
        match chunk_result {
            Some((index, entries, has_more)) => {
                chunk_count += 1;
                tracing::info!(
                    "📥 [list_directory] Chunk {}: {} entries, has_more={}, total_so_far={}",
                    index,
                    entries.len(),
                    has_more,
                    all_entries.len() + entries.len()
                );
                all_entries.extend(entries);
                if !has_more {
                    tracing::info!("✅ [list_directory] Last chunk received (has_more=false)");
                    break;
                }
                attempts = 0; // Reset on success
            }
            None => {
                attempts += 1;
                if attempts >= MAX_ATTEMPTS {
                    tracing::warn!("⚠️ [list_directory] TIMEOUT after {} attempts (3 seconds), chunks={}, entries={}",
                        MAX_ATTEMPTS, chunk_count, all_entries.len());
                    break; // Timeout
                }
                // Log every 25 attempts (500ms)
                if attempts % 25 == 0 {
                    tracing::debug!("⏳ [list_directory] Still waiting... {}/{} attempts", attempts, MAX_ATTEMPTS);
                }
            }
        }
    }

    tracing::info!("🏁 [list_directory] DONE: path='{}', chunks={}, entries={}",
        path, chunk_count, all_entries.len());
    Ok(all_entries)
}

/// Stream directory entries (DEPRECATED - for FRB codegen compatibility)
///
/// This function exists only for compatibility with generated code.
/// Use `list_directory()` instead (Future API, no race condition).
///
/// Phase VFS-Fix: Added delay after sink.add() to ensure Dart processes data.
pub fn stream_list_dir(
    path: String,
    sink: crate::frb_generated::StreamSink<Vec<DirEntry>>,
) -> Result<(), String> {
    use std::thread;
    use std::time::Duration;

    let path_clone = path.clone();

    // Spawn thread to convert Future → StreamSink
    thread::spawn(move || {
        let rt = match tokio::runtime::Runtime::new() {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("Failed to create tokio runtime: {}", e);
                return;
            }
        };

        let result = rt.block_on(async {
            list_directory(path_clone).await
        });

        match result {
            Ok(entries) => {
                tracing::info!("📤 [stream_list_dir] Sending {} entries", entries.len());
                match sink.add(entries) {
                    Ok(_) => {
                        // CRITICAL: Keep thread alive so Dart event loop processes onData
                        // Stream closes when this thread ends, so we must wait
                        tracing::info!("⏳ [stream_list_dir] Data sent, waiting for Dart to process...");
                        thread::sleep(Duration::from_millis(300));
                        tracing::info!("✅ [stream_list_dir] Done waiting");
                    }
                    Err(_) => {
                        tracing::warn!("⚠️ [stream_list_dir] Stream closed by Dart");
                    }
                }
            }
            Err(e) => {
                tracing::error!("❌ [stream_list_dir] Error: {}", e);
                let _ = sink.add_error(e);
                thread::sleep(Duration::from_millis(300));
            }
        }
    });

    Ok(())
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

// ===== VFS File Reading Functions - Phase 2 =====

/// Request server to read a file
///
/// Server responds with file content. Call receive_file_content() to get the result.
///
/// # Arguments
/// * `path` - Absolute path to file (e.g., "/tmp/file.txt", "~/Documents/file.md")
/// * `max_size` - Maximum file size in bytes (default: 100KB = 102400)
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn request_read_file(path: String, max_size: usize) -> Result<(), String> {
    tracing::info!("📄 [FRB] request_read_file: {} (max_size: {})", path, max_size);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.request_read_file(path, max_size).await
}

/// File content data (for Dart)
#[derive(Debug, Clone)]
#[frb(sync)]
pub struct FileContentData {
    /// File path
    pub path: String,
    /// File content (UTF-8 string)
    pub content: String,
    /// Content size in bytes
    pub size: usize,
    /// True if file was truncated due to size limit
    pub truncated: bool,
}

impl Default for FileContentData {
    fn default() -> Self {
        Self {
            path: String::new(),
            content: String::new(),
            size: 0,
            truncated: false,
        }
    }
}

/// Receive next file content from server (NON-BLOCKING)
///
/// Returns file content received from server.
/// Call repeatedly in a loop to process all responses.
/// Returns None if no content available yet.
///
/// # Returns
/// * `Some(FileContentData)` - File content received
/// * `None` - No content available yet
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn receive_file_content() -> Result<Option<FileContentData>, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;

    match client.receive_file_content().await? {
        Some((path, content, size, truncated)) => Ok(Some(FileContentData {
            path,
            content,
            size,
            truncated,
        })),
        None => Ok(None),
    }
}

/// Get file content buffer length (for monitoring)
///
/// Returns number of buffered file contents waiting to be processed.
#[frb]
pub async fn file_content_buffer_len() -> Result<usize, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    Ok(client.file_content_buffer_len().await)
}

// ===== Multi-Session Management - Phase 04 =====

/// Create a new PTY session with UUID
///
/// Sends CreateSession message to server. Server creates PTY in project directory.
///
/// # Arguments
/// * `project_path` - Absolute path to project directory
/// * `session_id` - UUID string for the session
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn create_session(project_path: String, session_id: String) -> Result<(), String> {
    tracing::info!("📝 [FRB] create_session: {} at {}", session_id, project_path);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.create_session(project_path, session_id).await
}

/// Check if session exists on server (for re-attach on app restart)
///
/// Sends CheckSession message. Server responds with SessionReAttach or SessionNotFound event.
///
/// # Arguments
/// * `session_id` - UUID string to check
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn check_session(session_id: String) -> Result<(), String> {
    tracing::info!("🔍 [FRB] check_session: {}", session_id);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.check_session(session_id).await
}

/// Switch active session
///
/// Sends SwitchSession message. Server responds with SessionHistory and SessionSwitched event.
/// Only the active session's output is pumped to the client.
///
/// # Arguments
/// * `session_id` - UUID string to switch to
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn switch_session(session_id: String) -> Result<(), String> {
    tracing::info!("🔄 [FRB] switch_session: {}", session_id);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.switch_session(session_id).await
}

/// Close a session
///
/// Sends CloseSession message. Server responds with SessionClosed event.
///
/// # Arguments
/// * `session_id` - UUID string to close
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn close_session(session_id: String) -> Result<(), String> {
    tracing::info!("❌ [FRB] close_session: {}", session_id);
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.close_session(session_id).await
}

/// List all active sessions
///
/// Sends ListSessions message. Server responds with text list via Output event.
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn list_sessions() -> Result<(), String> {
    tracing::info!("📋 [FRB] list_sessions");
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    client.list_sessions().await
}

/// Session history data (for Dart)
#[derive(Debug, Clone)]
#[frb(sync)]
pub struct SessionHistoryData {
    /// Session ID
    pub session_id: String,
    /// History lines (max 100)
    pub lines: Vec<String>,
}

/// Receive session history from server (NON-BLOCKING)
///
/// Returns history buffer for inactive session after switch.
/// Call repeatedly until None is returned.
///
/// # Returns
/// * `Some(SessionHistoryData)` - History received
/// * `None` - No history available yet
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn receive_session_history() -> Result<Option<SessionHistoryData>, String> {
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;

    match client.receive_session_history().await? {
        Some((session_id, lines)) => Ok(Some(SessionHistoryData { session_id, lines })),
        None => Ok(None),
    }
}

/// Get active session ID
///
/// Returns the UUID of the currently active session, or None if no session is active.
#[frb]
pub async fn get_active_session_id() -> Option<String> {
    let lock = QUIC_CLIENT.get_or_init(|| tokio::sync::RwLock::new(None));
    let client_guard = lock.read().await;

    if let Some(client_arc) = client_guard.as_ref() {
        let client = client_arc.lock().await;
        client.get_active_session_id().await
    } else {
        None
    }
}

// ===== Vibe Coding Session API =====
//
// Phase 02: Multi-PTY Session support
// These functions allow Flutter to manage multiple PTY sessions

/// Session command for Vibe Coding
///
/// Phase 02: Multi-session management
#[frb]
pub enum SessionCommand {
    /// Create new session
    Create { project_path: String, project_name: String },
    /// Switch active session
    Switch { session_id: String },
    /// Close session
    Close { session_id: String },
    /// List all sessions
    List,
}

/// Session data for Flutter
///
/// Phase 02: Session metadata
#[frb]
pub struct SessionData {
    pub id: String,
    pub project_name: String,
    pub project_path: String,
    pub status: String,
}

/// Execute session command
///
/// Phase 02: Entry point for session management
/// Note: This is a placeholder - actual multi-PTY requires backend session manager
#[frb]
pub async fn session_command(cmd: SessionCommand) -> Result<Vec<SessionData>, String> {
    match cmd {
        SessionCommand::List => {
            // Return empty list for now - Flutter manages sessions locally
            Ok(vec![])
        }
        SessionCommand::Create { project_path, project_name } => {
            // Placeholder - Flutter creates session locally
            tracing::info!("Session create request: {} at {}", project_name, project_path);
            Ok(vec![])
        }
        SessionCommand::Switch { session_id } => {
            tracing::info!("Session switch request: {}", session_id);
            Ok(vec![])
        }
        SessionCommand::Close { session_id } => {
            tracing::info!("Session close request: {}", session_id);
            Ok(vec![])
        }
    }
}

/// Unified Vibe input
///
/// Phase 02: Support for different input types
#[frb]
pub enum VibeInput {
    /// Plain text prompt
    Text { prompt: String },
    /// Special key (arrows, Ctrl+C, etc)
    Key { key_code: String },
    /// Raw bytes
    Raw { data: Vec<u8> },
}

/// Send input to specific session
///
/// Phase 02: Send input to a session
#[frb]
pub async fn send_vibe_input(_session_id: String, input: VibeInput) -> Result<(), String> {
    match input {
        VibeInput::Text { prompt } => {
            send_terminal_command(prompt).await
        }
        VibeInput::Key { key_code } => {
            // Convert key code to terminal escape sequence
            let seq = match key_code.as_str() {
                "ArrowUp" => "\x1b[A",
                "ArrowDown" => "\x1b[B",
                "Enter" => "\r",
                "CtrlC" => "\x03",
                _ => "",
            };
            send_terminal_command(seq.to_string()).await
        }
        VibeInput::Raw { data } => {
            // Send raw bytes
            let text = String::from_utf8_lossy(&data);
            send_terminal_command(text.into_owned()).await
        }
    }
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
