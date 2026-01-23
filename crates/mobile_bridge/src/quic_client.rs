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
use comacode_core::types::{NetworkMessage, TerminalCommand, FileEventType};
use quinn::{Endpoint, Connection, SendStream};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tracing::{info, error, debug, warn};

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
        let recv_task = tokio::spawn(async move {
            info!("🔄 [RECV_TASK] Background receive task started");
            let mut recv = recv_shared.lock().await;
            let mut read_buf = vec![0u8; 8192];

            loop {
                // Read from stream (blocking is OK in background task)
                match recv.read(&mut read_buf).await {
                    Ok(Some(n)) => {
                        if n > 0 {
                            // Decode and push to buffer
                            match MessageCodec::decode(&read_buf[..n]) {
                                Ok(NetworkMessage::Event(event)) => {
                                    info!("📥 [RECV_TASK] Received event, buffering");
                                    let mut buffer = event_buffer.lock().await;
                                    buffer.push(event);
                                }
                                // VFS Phase 1: Buffer DirChunk messages
                                // Cap at 100 chunks to prevent OOM (~15MB max)
                                Ok(NetworkMessage::DirChunk { ref entries, ref has_more, .. }) => {
                                    let mut buffer = dir_chunk_buffer.lock().await;
                                    if buffer.len() < 100 {
                                        info!("📥 [RECV_TASK] Received DirChunk, buffering ({}/100)", buffer.len() + 1);
                                        buffer.push(NetworkMessage::DirChunk {
                                            chunk_index: 0,
                                            total_chunks: 0,
                                            entries: entries.clone(),
                                            has_more: *has_more,
                                        });
                                    } else {
                                        warn!("📥 [RECV_TASK] DirChunk buffer full (100), dropping chunk");
                                    }
                                }
                                // VFS Phase 3: Buffer file watcher events
                                // Cap at 1000 events to prevent OOM (~500KB max)
                                Ok(msg @ NetworkMessage::FileEvent { .. })
                                | Ok(msg @ NetworkMessage::WatchStarted { .. })
                                | Ok(msg @ NetworkMessage::WatchError { .. }) => {
                                    let mut buffer = file_event_buffer.lock().await;
                                    if buffer.len() < 1000 {
                                        info!("📥 [RECV_TASK] Received file watcher event, buffering ({}/1000)", buffer.len() + 1);
                                        buffer.push(msg);
                                    } else {
                                        warn!("📥 [RECV_TASK] File event buffer full (1000), dropping event");
                                    }
                                }
                                // VFS Phase 2: Buffer FileContent messages
                                // Cap at 10 files to prevent OOM (~10MB max)
                                Ok(msg @ NetworkMessage::FileContent { .. }) => {
                                    let mut buffer = file_content_buffer.lock().await;
                                    if buffer.len() < 10 {
                                        info!("📥 [RECV_TASK] Received FileContent, buffering ({}/10)", buffer.len() + 1);
                                        buffer.push(msg);
                                    } else {
                                        warn!("📥 [RECV_TASK] FileContent buffer full (10), dropping response");
                                    }
                                }
                                Ok(msg) => {
                                    debug!("📥 [RECV_TASK] Received non-event message: {:?}", std::mem::discriminant(&msg));
                                }
                                Err(e) => {
                                    warn!("📥 [RECV_TASK] Failed to decode message: {}", e);
                                }
                            }
                        } else {
                            info!("📥 [RECV_TASK] Connection closed (EOF)");
                            break;
                        }
                    }
                    Ok(None) => {
                        info!("📥 [RECV_TASK] Connection closed (None)");
                        break;
                    }
                    Err(e) => {
                        error!("📥 [RECV_TASK] Read error: {}", e);
                        break;
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
}
