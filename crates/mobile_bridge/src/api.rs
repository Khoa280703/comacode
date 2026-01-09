//! Flutter Rust Bridge API
//!
//! FFI-safe functions for Dart integration
//!
//! Phase 04: Added QUIC client support
//! Phase 04.1: Fixed UB - replaced static mut with once_cell::sync::OnceCell

use comacode_core::{TerminalCommand, NetworkMessage, MessageCodec, TerminalEvent, QrPayload};
use flutter_rust_bridge::frb;
use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::quic_client::QuicClient;

/// Global client instance (thread-safe, no unsafe needed)
///
/// Using OnceCell ensures:
/// - One-time initialization guarantee
/// - Thread-safe access via atomic operations
/// - Zero undefined behavior
static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();

/// Initialize the QUIC client (internal helper)
///
/// This is called automatically by connect_to_host if not already initialized.
/// OnceCell ensures this only happens once.
fn init_quic_client(server_fingerprint: String) -> Result<(), String> {
    let client = QuicClient::new(server_fingerprint);
    QUIC_CLIENT.set(Arc::new(Mutex::new(client)))
        .map_err(|_| "Failed to initialize global client (already set)".to_string())
}

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
/// - First call: Initializes client and connects
/// - Subsequent calls: Returns error if already connected
#[frb]
pub async fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
) -> Result<(), String> {
    // Check if already initialized (OnceCell::get is thread-safe)
    if QUIC_CLIENT.get().is_some() {
        return Err(
            "Client already initialized. Please restart app to reset.".to_string()
        );
    }

    // Initialize client (one-time, thread-safe)
    init_quic_client(fingerprint)?;

    // Get client (safe unwrap - we just initialized it)
    let client_arc = QUIC_CLIENT.get()
        .ok_or("Failed to get initialized client")?;

    // Connect
    let mut client = client_arc.lock().await;
    client.connect(host, port, auth_token).await
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
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;

    let client = client_arc.lock().await;
    client.receive_event().await
}

/// Send command to remote terminal
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn send_terminal_command(command: String) -> Result<(), String> {
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;

    let client = client_arc.lock().await;
    client.send_command(command).await
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
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;

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
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;

    let client = client_arc.lock().await;
    client.resize_pty(rows, cols).await
}

/// Disconnect from host
///
/// # Errors
/// Returns "Not connected" if client not initialized.
#[frb]
pub async fn disconnect_from_host() -> Result<(), String> {
    let client_arc = QUIC_CLIENT.get()
        .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;

    let mut client = client_arc.lock().await;
    client.disconnect().await
}

/// Check if connected
///
/// Returns false if client not initialized or disconnected.
#[frb]
pub async fn is_connected() -> bool {
    if let Some(client_arc) = QUIC_CLIENT.get() {
        let client = client_arc.lock().await;
        client.is_connected().await
    } else {
        false
    }
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
