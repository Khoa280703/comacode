//! QUIC client for Flutter bridge
//!
//! Phase 04: Mobile App - QUIC client with TOFU verification
//! Phase 09: Background receive task - non-blocking event polling
//! Phase VFS-1: Directory listing with DirChunk support
//!
//! ## Implementation Notes
//!
//! Uses Quinn 0.11 + Rustls 0.23 with custom TOFU (Trust On First Use) certificate verifier.
//! The fingerprint is normalized (case-insensitive, separator-agnostic) before comparison.
//!
//! **Background Receive Task:** To prevent blocking Dart isolate's event loop,
//! receive operations run in a background Tokio task. Events are buffered in
//! Arc<Mutex<Vec>> and receive_event() polls from this buffer (non-blocking).

use comacode_core::{TerminalEvent, AuthToken};
use comacode_core::types::DirEntry;
use comacode_core::protocol::MessageCodec;
use comacode_core::types::{NetworkMessage, TerminalCommand, FileEventType, SessionMessage, TaggedOutput};
use quinn::{Endpoint, Connection, SendStream};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tracing::{info, error, debug, warn};
use bytes::{BytesMut, BufMut, Buf};

// Rustls imports for custom certificate verification
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature};
use rustls::DigitallySignedStruct;
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};

// SHA256 for fingerprint calculation
use sha2::{Digest, Sha256};

/// Custom certificate verifier for TOFU (Trust On First Use)
///
/// This verifier:
/// 1. Calculates SHA256 fingerprint of the server certificate
/// 2. Normalizes both expected and actual fingerprints (case-insensitive, no separators)
/// 3. Compares them for authentication
///
/// This eliminates the need for a CA infrastructure while providing
/// protection against MitM attacks.
#[derive(Debug)]
struct TofuVerifier {
    expected_fingerprint: String,
}

impl TofuVerifier {
    fn new(fingerprint: String) -> Self {
        Self {
            expected_fingerprint: fingerprint,
        }
    }

    /// Normalize fingerprint for comparison
    ///
    /// Handles various formats: "AA:BB:CC", "aa:bb:cc", "AABBCC", "aa-bb-cc"
    /// All become: "AABBCC" (uppercase, no separators)
    fn normalize_fingerprint(fp: &str) -> String {
        fp.chars()
            .filter(|c| c.is_alphanumeric()) // Remove ':', '-', spaces
            .map(|c| c.to_ascii_uppercase()) // Uppercase
            .collect()
    }

    /// Calculate SHA256 fingerprint from certificate
    ///
    /// Returns format: "AA:BB:CC:DD..." (human readable)
    fn calculate_fingerprint(&self, cert: &CertificateDer) -> String {
        let mut hasher = Sha256::new();
        hasher.update(cert.as_ref());
        let result = hasher.finalize();

        result
            .iter()
            .map(|b| format!("{:02X}", b))
            .collect::<Vec<String>>()
            .join(":")
    }
}

impl ServerCertVerifier for TofuVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        // Normalize both fingerprints before comparison
        let actual_clean = Self::normalize_fingerprint(&self.calculate_fingerprint(end_entity));
        let expected_clean = Self::normalize_fingerprint(&self.expected_fingerprint);

        debug!("Verifying cert - Match: {}", actual_clean == expected_clean);

        if actual_clean == expected_clean {
            Ok(ServerCertVerified::assertion())
        } else {
            // Log only partial fingerprint (first 4 and last 4 chars) for debugging
            let expected_prefix = &expected_clean[..4.min(expected_clean.len())];
            let expected_suffix = if expected_clean.len() > 4 {
                &expected_clean[expected_clean.len()-4..]
            } else {
                ""
            };
            let actual_prefix = &actual_clean[..4.min(actual_clean.len())];
            let actual_suffix = if actual_clean.len() > 4 {
                &actual_clean[actual_clean.len()-4..]
            } else {
                ""
            };

            error!(
                "Fingerprint mismatch! Expected: {}...{}, Got: {}...{}",
                expected_prefix, expected_suffix, actual_prefix, actual_suffix
            );
            Err(rustls::Error::General("Fingerprint mismatch".to_string()))
        }
    }

    // Delegate TLS 1.2 signature verification to ring provider
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    // Delegate TLS 1.3 signature verification to ring provider
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

/// QUIC client for Flutter bridge
///
/// Uses TOFU (Trust On First Use) with fingerprint-based certificate verification.
pub struct QuicClient {
    /// QUIC endpoint for client connections
    endpoint: Endpoint,
    /// Active QUIC connection (if any)
    connection: Option<Connection>,
    /// Expected server fingerprint for TOFU verification
    server_fingerprint: String,
    /// QUIC send stream for commands
    send_stream: Option<Arc<Mutex<SendStream>>>,
    /// Background task for receiving terminal events
    recv_task: Option<JoinHandle<()>>,
    /// Event buffer for background receive task
    /// Events from server are pushed here by background task
    event_buffer: Arc<Mutex<Vec<TerminalEvent>>>,
    /// DirChunk buffer for VFS directory listing
    dir_chunk_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
    /// File event buffer for VFS file watcher (Phase VFS-3)
    file_event_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
    /// File content buffer for VFS file reading (Phase VFS-2)
    file_content_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
    /// Session history buffer for multi-session support (Phase 04)
    /// Stores SessionHistory messages for inactive sessions
    session_history_buffer: Arc<Mutex<Vec<NetworkMessage>>>,
    /// Active session ID (Phase 04)
    active_session_id: Arc<Mutex<Option<String>>>,
}

impl QuicClient {
    /// Create new QUIC client with fingerprint for TOFU verification
    pub fn new(server_fingerprint: String) -> Self {
        // Create client endpoint bound to random port
        let endpoint = Endpoint::client("0.0.0.0:0".parse().unwrap())
            .expect("Failed to create QUIC client endpoint");

        Self {
            endpoint,
            connection: None,
            server_fingerprint,
            send_stream: None,
            recv_task: None,
            event_buffer: Arc::new(Mutex::new(Vec::new())),
            dir_chunk_buffer: Arc::new(Mutex::new(Vec::new())),
            file_event_buffer: Arc::new(Mutex::new(Vec::new())),
            file_content_buffer: Arc::new(Mutex::new(Vec::new())),
            session_history_buffer: Arc::new(Mutex::new(Vec::new())),
            active_session_id: Arc::new(Mutex::new(None)),
        }
    }

    /// Connect to remote host using QUIC with TOFU verification
    ///
    /// # Arguments
    /// * `host` - Server IP address or hostname
    /// * `port` - QUIC server port
    /// * `auth_token` - Authentication token (validated but not used in this phase)
    pub async fn connect(
        &mut self,
        host: String,
        port: u16,
        auth_token: String,
    ) -> Result<(), String> {
        // Validate inputs
        if host.is_empty() {
            return Err("Host cannot be empty".to_string());
        }
        if port == 0 {
            return Err("Port cannot be 0".to_string());
        }

        // Validate auth token format
        let token = AuthToken::from_hex(&auth_token)
            .map_err(|e| format!("Invalid auth token: {}", e))?;

        info!("Connecting to {}:{} with TOFU fingerprint verification...", host, port);

        // Step 1: Setup Rustls config with TOFU verifier
        let verifier = Arc::new(TofuVerifier::new(self.server_fingerprint.clone()));

        let rustls_config = rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth();

        // Step 2: Wrap into Quinn config using configure_client (Phase 05.1)
        let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(rustls_config)
            .map_err(|e| format!("Failed to create QUIC crypto config: {}", e))?;

        let client_config = comacode_core::transport::configure_client(Arc::new(quic_crypto));

        // Step 3: Connect to server
        let addr = format!("{}:{}", host, port)
            .parse::<std::net::SocketAddr>()
            .map_err(|e| format!("Invalid address: {}", e))?;

        // SNI string - not critical for TOFU but required by TLS
        let connecting = self
            .endpoint
            .connect_with(client_config, addr, "comacode-host")
            .map_err(|e| format!("Failed to initiate connection: {}", e))?;

        let connection = connecting.await.map_err(|e| format!("Connection failed: {}", e))?;

        info!("QUIC connection established to {}:{}", host, port);

        // Step 4: Open bidirectional stream (Phase 05.1)
        let (mut send, mut recv) = connection.open_bi().await
            .map_err(|e| format!("Failed to open stream: {}", e))?;

        // Step 5: Send Hello message with auth token
        let hello_msg = NetworkMessage::hello(Some(token));
        let encoded = MessageCodec::encode(&hello_msg)
            .map_err(|e| format!("Failed to encode hello: {}", e))?;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send hello: {}", e))?;

        // Step 6: Receive Hello ACK
        let mut read_buf = vec![0u8; 1024];
        let n = recv.read(&mut read_buf).await
            .map_err(|e| format!("Failed to read hello response: {}", e))?
            .ok_or_else(|| format!("Connection closed while waiting for hello"))?;

        if n == 0 {
            return Err("Server closed connection".to_string());
        }

        let response = MessageCodec::decode(&read_buf[..n])
            .map_err(|e| format!("Failed to decode hello response: {}", e))?;

        match response {
            NetworkMessage::Hello { .. } => {
                info!("Handshake successful");
            }
            _ => {
                return Err("Unexpected response from server".to_string());
            }
        }

        // Step 7: Store streams for subsequent operations
        let send_shared = Arc::new(Mutex::new(send));
        let recv_shared = Arc::new(Mutex::new(recv));

        self.send_stream = Some(send_shared.clone());

        // Step 8: Spawn background receive task (Phase 09)
        // This reads from QUIC stream continuously in background
        // and pushes events to event_buffer. receive_event() polls from buffer.
        let event_buffer = self.event_buffer.clone();
        let dir_chunk_buffer = self.dir_chunk_buffer.clone();
        let file_event_buffer = self.file_event_buffer.clone();
        let file_content_buffer = self.file_content_buffer.clone();
        let session_history_buffer = self.session_history_buffer.clone();
        let active_session_id = self.active_session_id.clone();
        let recv_task = tokio::spawn(async move {
            info!("🔄 [RECV_TASK] Background receive task started");
            let mut recv = recv_shared.lock().await;

            // Persistent buffer that grows as needed (fixes partial read bug)
            let mut recv_buffer = BytesMut::with_capacity(8192);
            let mut decode_failures = 0u32;
            const MAX_DECODE_FAILURES: u32 = 10;
            const MAX_MESSAGE_SIZE: usize = 16 * 1024 * 1024;

            loop {
                // Ensure capacity for next read
                if recv_buffer.remaining_mut() < 4096 {
                    recv_buffer.reserve(4096);
                }

                // Read into buffer (manually extend BytesMut)
                let mut temp_buf = vec![0u8; 8192];
                let n = match recv.read(&mut temp_buf).await {
                    Ok(Some(n)) => n,
                    Ok(None) => {
                        info!("📥 [RECV_TASK] Connection closed");
                        break;
                    }
                    Err(e) => {
                        error!("📥 [RECV_TASK] Read error: {}", e);
                        break;
                    }
                };

                if n == 0 {
                    break;
                }

                // Append to recv_buffer
                recv_buffer.extend_from_slice(&temp_buf[..n]);

                // Process ALL complete messages in buffer
                while recv_buffer.len() >= 4 {
                    // Read length prefix (big endian)
                    let len = u32::from_be_bytes([
                        recv_buffer[0], recv_buffer[1], recv_buffer[2], recv_buffer[3]
                    ]) as usize;

                    // Validate size (prevent DoS)
                    if len > MAX_MESSAGE_SIZE {
                        error!("❌ [RECV_TASK] Message too large: {} bytes. Killing connection.", len);
                        return;
                    }

                    // Check if complete
                    if recv_buffer.len() < 4 + len {
                        // Incomplete - wait for more data
                        break;
                    }

                    // Decode message (inline for error handling)
                    // MessageCodec::decode expects buffer WITH length prefix
                    match MessageCodec::decode(&recv_buffer[0..4 + len]) {
                        Ok(msg) => {
                            recv_buffer.advance(4 + len);
                            decode_failures = 0; // Reset on success

                            // Reset buffer if empty but capacity too large (memory management)
                            if recv_buffer.is_empty() && recv_buffer.capacity() > 65536 {
                                debug!("🧹 [RECV_TASK] Resetting buffer capacity");
                                recv_buffer = BytesMut::with_capacity(8192);
                            }

                            // Route message to appropriate buffer
                            match msg {
                                NetworkMessage::Event(event) => {
                                    info!("📥 [RECV_TASK] Received event");
                                    let mut buffer = event_buffer.lock().await;
                                    buffer.push(event);
                                }
                                NetworkMessage::DirChunk { ref entries, ref has_more, .. } => {
                                    let mut buffer = dir_chunk_buffer.lock().await;
                                    if buffer.len() < 100 {
                                        info!("📥 [RECV_TASK] Received DirChunk with {} entries", entries.len());
                                        buffer.push(NetworkMessage::DirChunk {
                                            chunk_index: 0,
                                            total_chunks: 0,
                                            entries: entries.clone(),
                                            has_more: *has_more,
                                        });
                                    } else {
                                        warn!("📥 [RECV_TASK] DirChunk buffer full, dropping");
                                    }
                                }
                                NetworkMessage::FileEvent { .. }
                                | NetworkMessage::WatchStarted { .. }
                                | NetworkMessage::WatchError { .. } => {
                                    let mut buffer = file_event_buffer.lock().await;
                                    if buffer.len() < 1000 {
                                        buffer.push(msg);
                                    } else {
                                        warn!("📥 [RECV_TASK] File event buffer full");
                                    }
                                }
                                NetworkMessage::FileContent { .. } => {
                                    let mut buffer = file_content_buffer.lock().await;
                                    if buffer.len() < 10 {
                                        buffer.push(msg);
                                    } else {
                                        warn!("📥 [RECV_TASK] FileContent buffer full");
                                    }
                                }
                                NetworkMessage::SessionHistory { .. } => {
                                    let mut buffer = session_history_buffer.lock().await;
                                    if buffer.len() < 100 {
                                        buffer.push(msg);
                                    } else {
                                        warn!("📥 [RECV_TASK] SessionHistory buffer full");
                                    }
                                }
                                NetworkMessage::TaggedOutput(TaggedOutput { session_id, data }) => {
                                    let current_active = active_session_id.lock().await;
                                    if current_active.as_ref() == Some(&session_id) {
                                        drop(current_active);
                                        let mut buffer = event_buffer.lock().await;
                                        buffer.push(TerminalEvent::Output { data });
                                    }
                                }
                                _ => {
                                    debug!("📥 [RECV_TASK] Unhandled message type");
                                }
                            }
                        }
                        Err(e) => {
                            error!("❌ [RECV_TASK] Decode error: {}", e);
                            recv_buffer.advance(4 + len); // Skip corrupted message
                            decode_failures += 1;

                            if decode_failures > MAX_DECODE_FAILURES {
                                error!("❌ [RECV_TASK] Too many decode failures ({}). Killing connection.", decode_failures);
                                return;
                            }
                        }
                    }
                }
            }
            info!("🛑 [RECV_TASK] Background receive task ended");
        });

        self.recv_task = Some(recv_task);
        self.connection = Some(connection);
        Ok(())
    }

    /// Receive next terminal event from server (NON-BLOCKING)
    ///
    /// Phase 09: Polls from event buffer populated by background task.
    /// Returns immediately if no events available (empty event).
    pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
        let mut buffer = self.event_buffer.lock().await;

        if buffer.is_empty() {
            // No events available - return empty immediately (non-blocking)
            Ok(TerminalEvent::output_str(""))
        } else {
            // Pop first event from buffer
            Ok(buffer.remove(0))
        }
    }

    /// Send command to remote terminal
    ///
    /// Phase 05.1: Sends command via QUIC stream
    pub async fn send_command(&self, command: String) -> Result<(), String> {
        info!("🔵 [QUIC_CLIENT] send_command called: '{}'", command);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| {
                error!("❌ [QUIC_CLIENT] No send_stream - not connected");
                "Not connected".to_string()
            })?;

        let cmd_msg = NetworkMessage::Command(TerminalCommand::new(command));
        let encoded = MessageCodec::encode(&cmd_msg)
            .map_err(|e| {
                error!("❌ [QUIC_CLIENT] Encode failed: {}", e);
                format!("Failed to encode command: {}", e)
            })?;

        info!("📤 [QUIC_CLIENT] Sending {} bytes", encoded.len());

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| {
                error!("❌ [QUIC_CLIENT] write_all failed: {}", e);
                format!("Failed to send command: {}", e)
            })?;

        info!("✅ [QUIC_CLIENT] Command sent successfully");
        Ok(())
    }

    /// Send raw input bytes to remote terminal (pure passthrough)
    ///
    /// Phase 08: Send raw keystrokes directly to PTY without String conversion.
    /// Use this for proper Ctrl+C, backspace, and other control characters.
    pub async fn send_raw_input(&self, data: Vec<u8>) -> Result<(), String> {
        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let input_msg = NetworkMessage::Input { data };
        let encoded = MessageCodec::encode(&input_msg)
            .map_err(|e| format!("Failed to encode input: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send input: {}", e))?;

        debug!("Sent raw input via QUIC");
        Ok(())
    }

    /// Resize PTY (for screen rotation support)
    ///
    /// Phase 05.1: Send resize event via QUIC to update PTY size on server
    pub async fn resize_pty(&self, rows: u16, cols: u16) -> Result<(), String> {
        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let resize_msg = NetworkMessage::Resize { rows, cols };
        let encoded = MessageCodec::encode(&resize_msg)
            .map_err(|e| format!("Failed to encode resize: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send resize: {}", e))?;

        debug!("Sent resize {}x{} via QUIC", rows, cols);
        Ok(())
    }

    // ===== VFS Methods - Phase 1 =====

    /// Request directory listing from server
    ///
    /// Sends ListDir message. Server responds with multiple DirChunk messages.
    /// Call receive_dir_chunk() to receive chunks until has_more == false.
    pub async fn request_list_dir(&self, path: String) -> Result<(), String> {
        info!("📁 [QUIC_CLIENT] request_list_dir: {}", path);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let list_dir_msg = NetworkMessage::ListDir {
            path,
            depth: None,  // Reserved for future
        };
        let encoded = MessageCodec::encode(&list_dir_msg)
            .map_err(|e| format!("Failed to encode ListDir: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send ListDir: {}", e))?;

        info!("✅ [QUIC_CLIENT] ListDir request sent");
        Ok(())
    }

    /// Receive next directory chunk from server (NON-BLOCKING)
    ///
    /// Returns (chunk_index, entries, has_more) tuple.
    /// Returns None if no chunks available yet.
    /// Call repeatedly until has_more == false.
    ///
    /// **Security**: Buffer capped at 100 chunks to prevent OOM.
    pub async fn receive_dir_chunk(&self) -> Result<Option<(u32, Vec<DirEntry>, bool)>, String> {
        let mut buffer = self.dir_chunk_buffer.lock().await;

        // Find first DirChunk message
        let pos = buffer.iter().position(|m| matches!(m, NetworkMessage::DirChunk { .. }));

        match pos {
            Some(idx) => {
                let msg = buffer.remove(idx);
                if let NetworkMessage::DirChunk { chunk_index, entries, has_more, .. } = msg {
                    info!("📥 [QUIC_CLIENT] Received DirChunk {}/? with {} entries, has_more={}",
                        chunk_index, entries.len(), has_more);
                    Ok(Some((chunk_index, entries, has_more)))
                } else {
                    unreachable!() // We checked above
                }
            }
            None => Ok(None),  // No chunks available
        }
    }

    /// Get dir chunk buffer length (for monitoring)
    pub async fn dir_chunk_buffer_len(&self) -> usize {
        self.dir_chunk_buffer.lock().await.len()
    }

    /// Disconnect from server
    pub async fn disconnect(&mut self) -> Result<(), String> {
        // Abort background receive task
        if let Some(task) = self.recv_task.take() {
            task.abort();
            info!("🛑 [QUIC_CLIENT] Background receive task aborted");
        }

        if let Some(conn) = &self.connection {
            conn.close(0u32.into(), b"Client disconnect");
        }
        self.connection = None;
        self.send_stream = None;

        // Clear buffers
        let mut buffer = self.event_buffer.lock().await;
        buffer.clear();
        let mut dir_buffer = self.dir_chunk_buffer.lock().await;
        dir_buffer.clear();
        let mut file_buffer = self.file_event_buffer.lock().await;
        file_buffer.clear();
        let mut file_content_buffer = self.file_content_buffer.lock().await;
        file_content_buffer.clear();

        Ok(())
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        match &self.connection {
            Some(conn) => conn.close_reason().is_none(),
            None => false,
        }
    }

    // ===== VFS Watcher Methods - Phase 3 =====

    /// Request server to watch a directory for changes
    ///
    /// Server will push FileEvent messages when files are created/modified/deleted.
    /// Call receive_file_event() to receive watcher events.
    pub async fn request_watch_dir(&self, path: String) -> Result<(), String> {
        info!("📁 [QUIC_CLIENT] request_watch_dir: {}", path);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let watch_msg = NetworkMessage::WatchDir { path };
        let encoded = MessageCodec::encode(&watch_msg)
            .map_err(|e| format!("Failed to encode WatchDir: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send WatchDir: {}", e))?;

        info!("✅ [QUIC_CLIENT] WatchDir request sent");
        Ok(())
    }

    /// Request server to stop watching a directory
    pub async fn request_unwatch_dir(&self, watcher_id: String) -> Result<(), String> {
        info!("📁 [QUIC_CLIENT] request_unwatch_dir: {}", watcher_id);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let unwatch_msg = NetworkMessage::UnwatchDir { watcher_id };
        let encoded = MessageCodec::encode(&unwatch_msg)
            .map_err(|e| format!("Failed to encode UnwatchDir: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send UnwatchDir: {}", e))?;

        info!("✅ [QUIC_CLIENT] UnwatchDir request sent");
        Ok(())
    }

    /// Receive next file watcher event from server (NON-BLOCKING)
    ///
    /// Returns Ok(Some(event)) if event available, Ok(None) if buffer empty.
    ///
    /// **Security**: Buffer capped at 1000 events to prevent OOM.
    pub async fn receive_file_event(&self) -> Result<Option<FileWatcherEventData>, String> {
        let mut buffer = self.file_event_buffer.lock().await;

        let pos = buffer.iter().position(|m| matches!(
            m,
            NetworkMessage::FileEvent { .. }
                | NetworkMessage::WatchStarted { .. }
                | NetworkMessage::WatchError { .. }
        ));

        match pos {
            Some(idx) => {
                let msg = buffer.remove(idx);
                Ok(Some(match msg {
                    NetworkMessage::FileEvent { watcher_id, path, event_type, timestamp } => {
                        FileWatcherEventData::FileEvent(FileWatcherEvent {
                            watcher_id,
                            path,
                            event_type,
                            timestamp,
                        })
                    }
                    NetworkMessage::WatchStarted { watcher_id } => {
                        FileWatcherEventData::Started(WatcherStartedEvent { watcher_id })
                    }
                    NetworkMessage::WatchError { watcher_id, error } => {
                        FileWatcherEventData::Error(WatcherErrorEvent { watcher_id, error })
                    }
                    _ => unreachable!(),
                }))
            }
            None => Ok(None),
        }
    }

    /// Get file event buffer length (for monitoring)
    pub async fn file_event_buffer_len(&self) -> usize {
        self.file_event_buffer.lock().await.len()
    }

    // ===== VFS File Reading Methods - Phase 2 =====

    /// Request server to read a file
    ///
    /// Server responds with FileContent message.
    /// Call receive_file_content() to receive the file content.
    pub async fn request_read_file(&self, path: String, max_size: usize) -> Result<(), String> {
        info!("📄 [QUIC_CLIENT] request_read_file: {} (max_size: {})", path, max_size);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let read_file_msg = NetworkMessage::ReadFile { path, max_size };
        let encoded = MessageCodec::encode(&read_file_msg)
            .map_err(|e| format!("Failed to encode ReadFile: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send ReadFile: {}", e))?;

        info!("✅ [QUIC_CLIENT] ReadFile request sent");
        Ok(())
    }

    /// Receive file content from server (NON-BLOCKING)
    ///
    /// Returns (path, content, size, truncated) tuple.
    /// Returns None if no file content available yet.
    pub async fn receive_file_content(&self) -> Result<Option<(String, String, usize, bool)>, String> {
        let mut buffer = self.file_content_buffer.lock().await;

        // Find first FileContent message
        let pos = buffer.iter().position(|m| matches!(m, NetworkMessage::FileContent { .. }));

        match pos {
            Some(idx) => {
                let msg = buffer.remove(idx);
                if let NetworkMessage::FileContent { path, content, size, truncated } = msg {
                    info!("📥 [QUIC_CLIENT] Received FileContent: {} bytes, truncated={}", size, truncated);
                    Ok(Some((path, content, size, truncated)))
                } else {
                    unreachable!() // We checked above
                }
            }
            None => Ok(None),  // No file content available
        }
    }

    /// Get file content buffer length (for monitoring)
    pub async fn file_content_buffer_len(&self) -> usize {
        self.file_content_buffer.lock().await.len()
    }

    // ===== Multi-Session Management - Phase 04 =====

    /// Create a new PTY session with UUID
    ///
    /// Sends CreateSession message to server. Server responds with SessionCreated event.
    ///
    /// # Arguments
    /// * `project_path` - Absolute path to project directory
    /// * `session_id` - UUID string for the session (from Flutter)
    pub async fn create_session(&self, project_path: String, session_id: String) -> Result<(), String> {
        info!("📝 [QUIC_CLIENT] create_session: {} at {}", session_id, project_path);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let session_msg = SessionMessage::CreateSession { project_path, session_id };
        let msg = NetworkMessage::Session(session_msg);
        let encoded = MessageCodec::encode(&msg)
            .map_err(|e| format!("Failed to encode CreateSession: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send CreateSession: {}", e))?;

        info!("✅ [QUIC_CLIENT] CreateSession request sent");
        Ok(())
    }

    /// Check if session exists on server (for re-attach)
    ///
    /// Sends CheckSession message. Server responds with SessionReAttach or SessionNotFound.
    ///
    /// # Arguments
    /// * `session_id` - UUID string to check
    pub async fn check_session(&self, session_id: String) -> Result<(), String> {
        info!("🔍 [QUIC_CLIENT] check_session: {}", session_id);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let session_msg = SessionMessage::CheckSession { session_id };
        let msg = NetworkMessage::Session(session_msg);
        let encoded = MessageCodec::encode(&msg)
            .map_err(|e| format!("Failed to encode CheckSession: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send CheckSession: {}", e))?;

        info!("✅ [QUIC_CLIENT] CheckSession request sent");
        Ok(())
    }

    /// Switch active session
    ///
    /// Sends SwitchSession message. Server responds with SessionHistory (if available)
    /// and SessionSwitched event. Only active session's output is pumped.
    ///
    /// # Arguments
    /// * `session_id` - UUID string to switch to
    pub async fn switch_session(&self, session_id: String) -> Result<(), String> {
        info!("🔄 [QUIC_CLIENT] switch_session: {}", session_id);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let session_msg = SessionMessage::SwitchSession { session_id: session_id.clone() };
        let msg = NetworkMessage::Session(session_msg);
        let encoded = MessageCodec::encode(&msg)
            .map_err(|e| format!("Failed to encode SwitchSession: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send SwitchSession: {}", e))?;

        // Update local active session ID
        let mut active_id = self.active_session_id.lock().await;
        *active_id = Some(session_id);
        drop(active_id);

        info!("✅ [QUIC_CLIENT] SwitchSession request sent");
        Ok(())
    }

    /// Close a session
    ///
    /// Sends CloseSession message. Server responds with SessionClosed event.
    ///
    /// # Arguments
    /// * `session_id` - UUID string to close
    pub async fn close_session(&self, session_id: String) -> Result<(), String> {
        info!("❌ [QUIC_CLIENT] close_session: {}", session_id);

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let session_msg = SessionMessage::CloseSession { session_id: session_id.clone() };
        let msg = NetworkMessage::Session(session_msg);
        let encoded = MessageCodec::encode(&msg)
            .map_err(|e| format!("Failed to encode CloseSession: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send CloseSession: {}", e))?;

        // Clear local active session ID if it was the closed one
        let mut active_id = self.active_session_id.lock().await;
        if active_id.as_ref() == Some(&session_id) {
            *active_id = None;
        }

        info!("✅ [QUIC_CLIENT] CloseSession request sent");
        Ok(())
    }

    /// List all active sessions
    ///
    /// Sends ListSessions message. Server responds with text list.
    pub async fn list_sessions(&self) -> Result<(), String> {
        info!("📋 [QUIC_CLIENT] list_sessions");

        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let session_msg = SessionMessage::ListSessions;
        let msg = NetworkMessage::Session(session_msg);
        let encoded = MessageCodec::encode(&msg)
            .map_err(|e| format!("Failed to encode ListSessions: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send ListSessions: {}", e))?;

        info!("✅ [QUIC_CLIENT] ListSessions request sent");
        Ok(())
    }

    /// Receive session history from server (NON-BLOCKING)
    ///
    /// Returns Ok(Some((session_id, lines))) if history available.
    /// Returns Ok(None) if no history available yet.
    ///
    /// Called after SwitchSession to receive history buffer for inactive session.
    pub async fn receive_session_history(&self) -> Result<Option<(String, Vec<String>)>, String> {
        let mut buffer = self.session_history_buffer.lock().await;

        // Find first SessionHistory message
        let pos = buffer.iter().position(|m| matches!(m, NetworkMessage::SessionHistory { .. }));

        match pos {
            Some(idx) => {
                let msg = buffer.remove(idx);
                if let NetworkMessage::SessionHistory { session_id, lines } = msg {
                    info!("📥 [QUIC_CLIENT] Received SessionHistory: {} lines", lines.len());
                    Ok(Some((session_id, lines)))
                } else {
                    unreachable!()
                }
            }
            None => Ok(None),
        }
    }

    /// Get active session ID
    pub async fn get_active_session_id(&self) -> Option<String> {
        self.active_session_id.lock().await.clone()
    }

    /// Set active session ID locally (for sync with server)
    pub async fn set_active_session_id(&self, session_id: String) {
        let mut active_id = self.active_session_id.lock().await;
        *active_id = Some(session_id);
    }
}

/// File watcher event (for FFI)
#[derive(Debug, Clone)]
pub struct FileWatcherEvent {
    pub watcher_id: String,
    pub path: String,
    pub event_type: FileEventType,
    pub timestamp: u64,
}

/// Watcher started event (for FFI)
#[derive(Debug, Clone)]
pub struct WatcherStartedEvent {
    pub watcher_id: String,
}

/// Watcher error event (for FFI)
#[derive(Debug, Clone)]
pub struct WatcherErrorEvent {
    pub watcher_id: String,
    pub error: String,
}

/// File watcher event data enum
///
/// Moved outside impl block for public visibility
#[derive(Debug, Clone)]
pub enum FileWatcherEventData {
    FileEvent(FileWatcherEvent),
    Started(WatcherStartedEvent),
    Error(WatcherErrorEvent),
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test fingerprint normalization
    #[test]
    fn test_normalize_fingerprint() {
        // Various input formats should normalize to same output
        assert_eq!(TofuVerifier::normalize_fingerprint("AA:BB:CC"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("aa:bb:cc"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("aabbcc"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("aa-bb-cc"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("AA BB CC"), "AABBCC");
        assert_eq!(TofuVerifier::normalize_fingerprint("Aa:Bb-Cc"), "AABBCC");
    }

    // Test fingerprint calculation with known input
    #[test]
    fn test_fingerprint_calculation() {
        let verifier = TofuVerifier::new("AA:BB:CC".to_string());

        // Create a dummy certificate (1 byte)
        let cert = CertificateDer::from(vec![0x42u8]);

        // SHA256 of [0x42] = "9F03A...C6F" (specific hash)
        let fingerprint = verifier.calculate_fingerprint(&cert);

        // Should be 32 bytes = 64 hex chars = 95 chars with colons
        assert!(fingerprint.len() == 95); // "XX:XX:..." format
        assert!(fingerprint.chars().filter(|c| *c == ':').count() == 31);
    }

    #[test]
    fn test_quic_client_creation() {
        // Note: QuicClient::new() requires tokio runtime for Endpoint creation
        // We test the fingerprint field is set correctly when creating client with valid runtime
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let client = QuicClient::new("AA:BB:CC".to_string());
            assert_eq!(client.server_fingerprint, "AA:BB:CC");
            assert!(client.connection.is_none());
        });
    }

    #[tokio::test]
    async fn test_quic_client_not_connected_initially() {
        let client = QuicClient::new("AA:BB:CC".to_string());
        assert!(!client.is_connected().await);
    }

    #[tokio::test]
    async fn test_quic_client_invalid_host() {
        let mut client = QuicClient::new("AA:BB:CC".to_string());
        let token = AuthToken::generate();
        let result = client.connect("".to_string(), 8443, token.to_hex()).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Host cannot be empty"));
    }

    #[tokio::test]
    async fn test_quic_client_invalid_port() {
        let mut client = QuicClient::new("AA:BB:CC".to_string());
        let token = AuthToken::generate();
        let result = client.connect("127.0.0.1".to_string(), 0, token.to_hex()).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Port cannot be 0"));
    }

    #[tokio::test]
    async fn test_quic_client_invalid_token() {
        let mut client = QuicClient::new("AA:BB:CC".to_string());
        let result = client.connect("127.0.0.1".to_string(), 8443, "invalid".to_string()).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid auth token"));
    }

    // Phase 1 fix: BytesMut buffer decoding tests
    #[test]
    fn test_bytesmut_partial_message() {
        use bytes::BytesMut;

        // Test partial message handling with BytesMut
        let msg = NetworkMessage::Close;
        let encoded = MessageCodec::encode(&msg).unwrap();

        // Verify length prefix format
        assert!(encoded.len() >= 4);
        let payload_len = u32::from_be_bytes([encoded[0], encoded[1], encoded[2], encoded[3]]) as usize;
        assert_eq!(payload_len + 4, encoded.len());

        // Decode with full buffer (happy path)
        let mut buf = BytesMut::with_capacity(8192);
        buf.extend_from_slice(&encoded);
        let decoded = MessageCodec::decode(&buf).unwrap();
        assert!(matches!(decoded, NetworkMessage::Close));
    }

    #[test]
    fn test_bytesmut_advance() {
        use bytes::BytesMut;

        // Test buffer advance (critical for processing multiple messages)
        let msg1 = NetworkMessage::Close;
        let msg2 = NetworkMessage::Pong { timestamp: 12345 };

        let enc1 = MessageCodec::encode(&msg1).unwrap();
        let enc2 = MessageCodec::encode(&msg2).unwrap();

        let mut buf = BytesMut::with_capacity(8192);
        buf.extend_from_slice(&enc1);
        buf.extend_from_slice(&enc2);

        // Process first message
        let len1 = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
        let total1 = 4 + len1;
        assert!(buf.len() >= total1);
        buf.advance(total1); // Move cursor past first message

        // Process second message
        let len2 = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
        let total2 = 4 + len2;
        assert!(buf.len() >= total2);
        buf.advance(total2);

        // Buffer should now be empty at cursor
        assert_eq!(buf.len(), 0);
    }

    #[test]
    fn test_bytesmut_large_dirchunk() {
        use bytes::BytesMut;

        // Create a large DirChunk (100 entries)
        let entries: Vec<DirEntry> = (0..100).map(|i| DirEntry {
            name: format!("file{}", i),
            path: format!("/path/file{}", i),
            is_dir: i % 2 == 0,
            size: Some(i * 1024),
            modified: Some(i as u64),
            is_symlink: false,
            permissions: None,
        }).collect();

        let msg = NetworkMessage::DirChunk {
            chunk_index: 0,
            total_chunks: 1,
            entries: entries.clone(),
            has_more: false,
        };

        let encoded = MessageCodec::encode(&msg).unwrap();

        // BytesMut can handle any size (grows as needed)
        let mut buf = BytesMut::with_capacity(8192);
        buf.extend_from_slice(&encoded);

        // Decode successfully
        let decoded = MessageCodec::decode(&buf).unwrap();
        match decoded {
            NetworkMessage::DirChunk { entries: decoded_entries, .. } => {
                assert_eq!(decoded_entries.len(), 100);
            }
            _ => panic!("Expected DirChunk"),
        }
    }
}
