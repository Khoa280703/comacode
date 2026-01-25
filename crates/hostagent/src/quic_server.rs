//! QUIC server for terminal connections
//!
//! Provides encrypted QUIC endpoint for mobile client connections.

use anyhow::{Context, Result};
use comacode_core::{
    protocol::MessageCodec,
    transport::{configure_server, stream::pump_pty_to_quic, stream::pump_pty_to_quic_tagged},
    types::{NetworkMessage, SessionMessage, TerminalEvent},
};
use quinn::{Endpoint, TokioRuntime};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{oneshot, Mutex};
use tokio_stream::StreamExt;
use rcgen::KeyPair;

use crate::auth::TokenStore;
use crate::ratelimit::RateLimiterStore;
use crate::session::SessionManager;
use crate::vfs;
use crate::vfs_watcher::WatcherManager;

/// QUIC server for terminal connections
pub struct QuicServer {
    /// QUIC endpoint
    endpoint: Endpoint,
    /// Session manager for PTY instances
    session_mgr: Arc<SessionManager>,
    /// Token store for authentication validation
    token_store: Arc<TokenStore>,
    /// Rate limiter for auth failure tracking
    rate_limiter: Arc<RateLimiterStore>,
    /// File watcher manager for VFS (Phase VFS-3)
    watcher_mgr: Arc<WatcherManager>,
    /// Shutdown signal sender
    shutdown_tx: Option<oneshot::Sender<()>>,
}

impl QuicServer {
    /// Create new QUIC server with self-signed certificate
    pub async fn new(
        bind_addr: SocketAddr,
        token_store: Arc<TokenStore>,
        rate_limiter: Arc<RateLimiterStore>,
    ) -> Result<(Self, CertificateDer<'static>, PrivateKeyDer<'static>)> {
        // Generate self-signed certificate ONCE
        let (cert, key_pair) = generate_cert_with_keypair()?;

        // Serialize key twice - once for config, once for return
        let key_der = key_pair.serialize_der();
        let key_for_config = PrivateKeyDer::Pkcs8(key_der.clone().into());
        let key_for_return = PrivateKeyDer::Pkcs8(key_der.into());

        // Configure TLS using transport module (Phase 05.1)
        let cert_vec = vec![cert.clone()];
        let cfg = configure_server(cert_vec, key_for_config)
            .context("Failed to configure server")?;

        // Bind UDP socket
        let socket = std::net::UdpSocket::bind(bind_addr)
            .context("Failed to bind UDP socket")?;

        // Create endpoint with Tokio runtime
        let runtime = Arc::new(TokioRuntime);
        let endpoint = Endpoint::new(Default::default(), Some(cfg), socket, runtime)
            .context("Failed to create QUIC endpoint")?;

        tracing::info!("QUIC server listening on {}", bind_addr);

        Ok((
            Self {
                endpoint,
                session_mgr: Arc::new(SessionManager::new()),
                token_store,
                rate_limiter,
                watcher_mgr: Arc::new(WatcherManager::new()),
                shutdown_tx: None,
            },
            cert,
            key_for_return, // Return SAME key bytes, not regenerated
        ))
    }

    /// Run server (accepts connections indefinitely)
    pub async fn run(&mut self) -> Result<()> {
        let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
        self.shutdown_tx = Some(shutdown_tx);

        // Spawn session cleanup task
        let session_mgr = Arc::clone(&self.session_mgr);
        tokio::spawn(async move {
            let _cleanup_handle = session_mgr.spawn_cleanup_task();
            // Keep cleanup task running
            loop {
                tokio::time::sleep(Duration::from_secs(60)).await;
            }
        });

        // Spawn token cleanup task (hourly)
        let token_store = Arc::clone(&self.token_store);
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(3600));
            loop {
                interval.tick().await;
                let cleaned = token_store.cleanup_expired().await;
                if cleaned > 0 {
                    tracing::info!("Cleaned {} expired tokens", cleaned);
                }
            }
        });

        // Accept connections loop
        loop {
            tokio::select! {
                // Accept incoming connection
                incoming = self.endpoint.accept() => {
                    match incoming {
                        Some(incoming) => {
                            let session_mgr = Arc::clone(&self.session_mgr);
                            let token_store = Arc::clone(&self.token_store);
                            let rate_limiter = Arc::clone(&self.rate_limiter);
                            let watcher_mgr = Arc::clone(&self.watcher_mgr);
                            tokio::spawn(async move {
                                if let Err(e) = Self::handle_connection(incoming, session_mgr, token_store, rate_limiter, watcher_mgr).await {
                                    tracing::error!("Connection error: {}", e);
                                }
                            });
                        }
                        None => {
                            tracing::warn!("Endpoint closed");
                            break;
                        }
                    }
                }
                // Shutdown signal
                _ = &mut shutdown_rx => {
                    tracing::info!("Shutdown signal received");
                    break;
                }
            }
        }

        Ok(())
    }

    /// Handle single connection
    async fn handle_connection(
        incoming: quinn::Incoming,
        session_mgr: Arc<SessionManager>,
        token_store: Arc<TokenStore>,
        rate_limiter: Arc<RateLimiterStore>,
        watcher_mgr: Arc<WatcherManager>,
    ) -> Result<()> {
        // Accept the connection - returns Result<Connecting, ConnectionError>
        let connecting = incoming.accept()?;
        let connection = connecting.await?;

        let remote_addr = connection.remote_address();
        tracing::info!("Connection from {}", remote_addr);

        // Handle bi-directional streams
        loop {
            match connection.accept_bi().await {
                Ok((send, recv)) => {
                    let session_mgr = Arc::clone(&session_mgr);
                    let token_store = Arc::clone(&token_store);
                    let rate_limiter = Arc::clone(&rate_limiter);
                    let watcher_mgr = Arc::clone(&watcher_mgr);
                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_stream(send, recv, session_mgr, token_store, rate_limiter, watcher_mgr, remote_addr).await {
                            tracing::error!("Stream error: {}", e);
                        }
                    });
                }
                Err(quinn::ConnectionError::ApplicationClosed(_)) | Err(quinn::ConnectionError::LocallyClosed) => {
                    tracing::info!("Connection closed");
                    break;
                }
                Err(e) => {
                    tracing::error!("Accept stream error: {}", e);
                    break;
                }
            }
        }

        Ok(())
    }

    /// Handle single bi-directional stream
    async fn handle_stream(
        send: quinn::SendStream,
        mut recv: quinn::RecvStream,
        session_mgr: Arc<SessionManager>,
        token_store: Arc<TokenStore>,
        rate_limiter: Arc<RateLimiterStore>,
        watcher_mgr: Arc<WatcherManager>,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        let mut session_id: Option<u64> = None;  // Legacy session ID
        let mut active_session_id: Option<String> = None;  // Phase 04: Active UUID session
        let mut authenticated = false;
        let mut pty_task: Option<tokio::task::JoinHandle<()>> = None;
        let mut pending_resize: Option<(u16, u16)> = None; // Store (rows, cols) before session created

        // Share send stream for PTY output forwarding
        let send_shared = Arc::new(Mutex::new(send));

        // Message receive loop - read length-prefixed messages properly
        let mut recv_buffer = Vec::new(); // Buffer for incomplete reads

        loop {
            // Try to read some data
            let mut read_buf = [0u8; 8192];
            let n = match recv.read(&mut read_buf).await {
                Ok(Some(0)) => {
                    tracing::info!("Connection closed by client (EOF)");
                    break;
                }
                Ok(Some(n)) => n,
                Ok(None) => {
                    tracing::info!("Connection closed by client (None)");
                    break;
                }
                Err(e) => {
                    tracing::error!("Read error: {}", e);
                    break;
                }
            };

            // Append to recv buffer
            recv_buffer.extend_from_slice(&read_buf[..n]);
            tracing::debug!("Received {} bytes, buffer size: {}", n, recv_buffer.len());

            // Process all complete messages in buffer
            while let Some((msg, remaining)) = Self::try_decode_message(&recv_buffer) {
                recv_buffer = remaining.to_vec();

                tracing::info!("Received message: {:?}", std::mem::discriminant(&msg));

                // Handle message
                match msg {
                    NetworkMessage::Hello { ref protocol_version, ref app_version, auth_token, .. } => {
                    tracing::info!("Client hello protocol_version={}, app_version={}", protocol_version, app_version);

                    // Phase 07-A: AUTH VALIDATION (P0 fix)
                    let token_valid = if let Some(token) = auth_token {
                        token_store.validate(&token).await
                    } else {
                        tracing::warn!("No auth token provided from {}", peer_addr);
                        false
                    };

                    if !token_valid {
                        tracing::warn!("Auth failed for IP: {}", peer_addr);

                        // Record failure for rate limiting
                        let _ = rate_limiter.record_auth_failure(peer_addr.ip()).await;

                        // Send error response and close
                        let mut send_lock = send_shared.lock().await;
                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::hello(None)).await;
                        break;
                    }

                    // Reset auth failures on success
                    rate_limiter.reset_auth_failures(peer_addr.ip()).await;
                    authenticated = true;
                    tracing::info!("Client authenticated: {}", peer_addr);

                    // Validate protocol version
                    if let Err(e) = msg.validate_handshake() {
                        tracing::error!("Handshake validation failed: {}", e);
                        // Send error and close
                        let mut send_lock = send_shared.lock().await;
                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::hello(None)).await;
                        break;
                    }

                    // Respond with Hello
                    let response = NetworkMessage::hello(None);
                    let mut send_lock = send_shared.lock().await;
                    Self::send_message(&mut *send_lock, &response).await?;
                    }
                    NetworkMessage::Input { data } => {
                    // Raw input bytes - pure passthrough to PTY
                    // PTY handles echo & signal generation (Ctrl+C = SIGINT)
                    if !authenticated {
                        tracing::warn!("Input received before authentication from {}", peer_addr);
                        break;
                    }

                    // Phase 04: Check for active UUID session first, then legacy session
                    if let Some(ref uuid) = active_session_id {
                        // Write to UUID session
                        if let Err(e) = session_mgr.write_to_uuid_session(uuid, &data).await {
                            tracing::error!("Failed to write input to UUID session {}: {}", uuid, e);
                        }
                    } else if let Some(id) = session_id {
                        // Write raw bytes directly to legacy PTY
                        if let Err(e) = session_mgr.write_to_session(id, &data).await {
                            tracing::error!("Failed to write input to PTY: {}", e);
                        }
                    } else {
                        // Spawn new session with terminal configuration
                        let _ = Self::spawn_session_with_config(
                            &session_mgr,
                            pending_resize,
                            &mut pty_task,
                            &mut session_id,
                            &send_shared,
                            &data,
                        ).await;
                    }
                    }
                    NetworkMessage::Command(cmd) => {
                    // Legacy: Command with String text
                    // Still supported for backward compatibility
                    // Use Input instead for raw byte passthrough
                    if !authenticated {
                        tracing::warn!("Command received before authentication from {}", peer_addr);
                        break;
                    }

                    // Phase 04: Check for active UUID session first, then legacy session
                    if let Some(ref uuid) = active_session_id {
                        if let Err(e) = session_mgr.write_to_uuid_session(uuid, cmd.text.as_bytes()).await {
                            tracing::error!("Failed to write command to UUID session {}: {}", uuid, e);
                        }
                    } else if let Some(id) = session_id {
                        if let Err(e) = session_mgr.write_to_session(id, cmd.text.as_bytes()).await {
                            tracing::error!("Failed to write to PTY: {}", e);
                        }
                    } else {
                        // Spawn new session with terminal configuration (legacy Command path)
                        let _ = Self::spawn_session_with_config(
                            &session_mgr,
                            pending_resize,
                            &mut pty_task,
                            &mut session_id,
                            &send_shared,
                            cmd.text.as_bytes(),
                        ).await;
                    }
                    }
                    NetworkMessage::Ping { timestamp } => {
                    // Respond with Pong
                    let response = NetworkMessage::pong(timestamp);
                    let mut send_lock = send_shared.lock().await;
                    Self::send_message(&mut *send_lock, &response).await?;
                    }
                    NetworkMessage::Resize { rows, cols } => {
                    // Phase 04: Check for active UUID session first, then legacy session
                    if let Some(ref uuid) = active_session_id {
                        if let Err(e) = session_mgr.resize_uuid_session(uuid, rows, cols).await {
                            tracing::error!("Failed to resize UUID session {}: {}", uuid, e);
                        }
                    } else if let Some(id) = session_id {
                        if let Err(e) = session_mgr.resize_session(id, rows, cols).await {
                            tracing::error!("Failed to resize PTY: {}", e);
                        }
                    } else {
                        // Store pending resize for when session is created
                        pending_resize = Some((rows, cols));
                        tracing::debug!("Stored pending resize: {}x{}", rows, cols);
                    }
                    }
                    NetworkMessage::Close => {
                        tracing::info!("Received Close message");
                        break;
                    }
                    // ===== VFS: Directory Listing - Phase 1 =====
                    NetworkMessage::ListDir { path, depth: _ } => {
                        if !authenticated {
                            tracing::warn!("ListDir received before authentication from {}", peer_addr);
                            break;
                        }

                        tracing::info!("ListDir request: {}", path);

                        let path_buf = PathBuf::from(&path);

                        // Check if path exists
                        if !path_buf.exists() {
                            let error_msg = format!("Path not found: {}", path);
                            tracing::warn!("{}", error_msg);
                            let mut send_lock = send_shared.lock().await;
                            let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                comacode_core::types::TerminalEvent::Error {
                                    message: error_msg,
                                }
                            )).await;
                            break;
                        }

                        // Read directory
                        match vfs::read_directory(&path_buf).await {
                            Ok(entries) => {
                                // Security: Limit total entries to prevent DoS (max 10,000 entries)
                                const MAX_ENTRIES: usize = 10_000;
                                let (entries, entry_count) = if entries.len() > MAX_ENTRIES {
                                    tracing::warn!("Directory has {} entries, limiting to {}", entries.len(), MAX_ENTRIES);
                                    (entries.into_iter().take(MAX_ENTRIES).collect::<Vec<_>>(), MAX_ENTRIES)
                                } else {
                                    let count = entries.len();
                                    (entries, count)
                                };

                                // Chunk into batches of 150
                                let mut chunks = vfs::chunk_entries(entries, 150);

                                // Phase VFS-Fix: ALWAYS send at least one chunk, even if empty
                                // This prevents client timeout on empty directories
                                if chunks.is_empty() {
                                    tracing::info!("Directory empty, sending empty chunk");
                                    chunks = vec![vec![]];
                                }

                                let total = chunks.len() as u32;

                                tracing::info!("Sending {} chunks ({} entries)", total, entry_count);

                                for (i, chunk) in chunks.iter().enumerate() {
                                    let msg = NetworkMessage::DirChunk {
                                        chunk_index: i as u32,
                                        total_chunks: total,
                                        entries: chunk.clone(),
                                        has_more: i < chunks.len() - 1,
                                    };
                                    let mut send_lock = send_shared.lock().await;
                                    if let Err(e) = Self::send_message(&mut *send_lock, &msg).await {
                                        tracing::error!("Failed to send DirChunk: {}", e);
                                        break;
                                    }
                                }

                                tracing::info!("ListDir completed: {} chunks sent", total);
                            }
                            Err(e) => {
                                let error_msg = format!("Failed to read directory: {}", e);
                                tracing::error!("{}", error_msg);
                                let mut send_lock = send_shared.lock().await;
                                let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                    comacode_core::types::TerminalEvent::Error {
                                        message: error_msg,
                                    }
                                )).await;
                            }
                        }
                    }
                    // ===== VFS: File Watcher - Phase 3 =====
                    NetworkMessage::WatchDir { path } => {
                        if !authenticated {
                            tracing::warn!("WatchDir received before authentication from {}", peer_addr);
                            break;
                        }

                        tracing::info!("WatchDir request: {}", path);

                        let path_buf = PathBuf::from(&path);

                        // Check if path exists and is a directory
                        if !path_buf.exists() {
                            let error_msg = format!("Path not found: {}", path);
                            tracing::warn!("{}", error_msg);
                            let mut send_lock = send_shared.lock().await;
                            let _ = Self::send_message(&mut *send_lock, &NetworkMessage::WatchError {
                                watcher_id: format!("watch_{}", session_id.unwrap_or(0)),
                                error: error_msg,
                            }).await;
                            break;
                        }

                        if !path_buf.is_dir() {
                            let error_msg = format!("Path is not a directory: {}", path);
                            tracing::warn!("{}", error_msg);
                            let mut send_lock = send_shared.lock().await;
                            let _ = Self::send_message(&mut *send_lock, &NetworkMessage::WatchError {
                                watcher_id: format!("watch_{}", session_id.unwrap_or(0)),
                                error: error_msg,
                            }).await;
                            break;
                        }

                        // Start watching
                        let watcher_id = format!("watch_{}", session_id.unwrap_or(0));
                        let watcher_mgr_clone: Arc<WatcherManager> = Arc::clone(&watcher_mgr);
                        let send_clone = send_shared.clone();

                        // Spawn watch task
                        if let Err(e) = watcher_mgr_clone.watch_directory(
                            watcher_id.clone(),
                            &path_buf,
                            move |event| {
                                let msg = NetworkMessage::FileEvent {
                                    watcher_id: event.watcher_id.clone(),
                                    path: event.path,
                                    event_type: event.event_type,
                                    timestamp: event.timestamp,
                                };

                                // Send event to client
                                let send = send_clone.clone();
                                tokio::spawn(async move {
                                    let mut send_lock = send.lock().await;
                                    let _ = Self::send_message(&mut *send_lock, &msg).await;
                                });
                            },
                        ).await {
                            tracing::error!("Failed to start watcher: {}", e);
                            let mut send_lock = send_shared.lock().await;
                            let _ = Self::send_message(&mut *send_lock, &NetworkMessage::WatchError {
                                watcher_id: watcher_id.clone(),
                                error: format!("Failed to start watcher: {}", e),
                            }).await;
                            break;
                        }

                        // Send WatchStarted confirmation
                        let mut send_lock = send_shared.lock().await;
                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::WatchStarted {
                            watcher_id,
                        }).await;
                    }
                    NetworkMessage::UnwatchDir { watcher_id } => {
                        if !authenticated {
                            tracing::warn!("UnwatchDir received before authentication from {}", peer_addr);
                            break;
                        }

                        tracing::info!("UnwatchDir request: {}", watcher_id);

                        // Stop watching
                        if let Err(e) = watcher_mgr.unwatch(&watcher_id).await {
                            tracing::warn!("Failed to unwatch {}: {}", watcher_id, e);
                        }
                    }
                    // ===== VFS: File Reading - Phase 2 =====
                    NetworkMessage::ReadFile { path, max_size } => {
                        if !authenticated {
                            tracing::warn!("ReadFile received before authentication from {}", peer_addr);
                            break;
                        }

                        tracing::info!("ReadFile request: {} (max_size: {})", path, max_size);

                        let path_buf = PathBuf::from(&path);

                        // Security: Validate path is within allowed boundaries
                        // Use current directory as allowed_base to prevent path traversal attacks
                        let current_dir = std::env::current_dir()
                            .unwrap_or_else(|_| PathBuf::from("/"));

                        if let Err(e) = crate::vfs::validate_path(&path_buf, &current_dir) {
                            tracing::warn!("ReadFile path validation failed: {}", e);
                            // Return error response
                            let response = NetworkMessage::FileContent {
                                path: path.clone(),
                                content: String::new(),
                                size: 0,
                                truncated: false,
                            };
                            let mut send_lock = send_shared.lock().await;
                            let _ = Self::send_message(&mut *send_lock, &response).await;
                            continue;
                        }

                        let response = match crate::vfs::read_file(&path_buf, max_size).await {
                            Ok(content) => {
                                let size = content.len();
                                NetworkMessage::FileContent {
                                    path: path.clone(),
                                    content,
                                    size,
                                    truncated: false,
                                }
                            }
                            Err(e) => {
                                // Return error as FileContent with empty content
                                tracing::warn!("ReadFile failed: {}", e);
                                NetworkMessage::FileContent {
                                    path: path.clone(),
                                    content: String::new(),
                                    size: 0,
                                    truncated: false,
                                }
                            }
                        };

                        let mut send_lock = send_shared.lock().await;
                        let _ = Self::send_message(&mut *send_lock, &response).await;
                    }
                    // ===== Multi-Session Support - Phase 04 =====
                    NetworkMessage::Session(session_msg) => {
                        if !authenticated {
                            tracing::warn!("Session message received before authentication from {}", peer_addr);
                            break;
                        }

                        tracing::info!("Session message: {:?}", std::mem::discriminant(&session_msg));

                        match session_msg {
                            SessionMessage::CreateSession { project_path, session_id } => {
                                tracing::info!("CreateSession: project={}, session={}", project_path, session_id);

                                // Validate project path exists
                                let path_buf = PathBuf::from(&project_path);
                                if !path_buf.exists() {
                                    let error_msg = format!("Project path not found: {}", project_path);
                                    tracing::warn!("{}", error_msg);
                                    let mut send_lock = send_shared.lock().await;
                                    let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                        TerminalEvent::Error { message: error_msg },
                                    )).await;
                                    break;
                                }

                                // Build terminal config
                                let mut config = comacode_core::terminal::TerminalConfig::default();
                                if let Some((rows, cols)) = pending_resize {
                                    config.rows = rows;
                                    config.cols = cols;
                                    config.env.push(("COLUMNS".to_string(), cols.to_string()));
                                    config.env.push(("LINES".to_string(), rows.to_string()));
                                }

                                // Create UUID session
                                match session_mgr.create_session_with_uuid(
                                    session_id.clone(),
                                    config,
                                    &project_path,
                                ).await {
                                    Ok(()) => {
                                        // Send SessionCreated event
                                        let mut send_lock = send_shared.lock().await;
                                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                            TerminalEvent::session_created(session_id.clone()),
                                        )).await;

                                        tracing::info!("Session {} created for project {}", session_id, project_path);
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to create session {}: {}", session_id, e);
                                        let mut send_lock = send_shared.lock().await;
                                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                            TerminalEvent::Error { message: format!("Failed to create session: {}", e) },
                                        )).await;
                                    }
                                }
                            }
                            SessionMessage::CheckSession { session_id } => {
                                tracing::info!("CheckSession: {}", session_id);

                                let exists = session_mgr.session_exists(&session_id).await;
                                let event = if exists {
                                    TerminalEvent::session_reattach(session_id.clone())
                                } else {
                                    TerminalEvent::session_not_found(session_id.clone())
                                };

                                let mut send_lock = send_shared.lock().await;
                                let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(event)).await;
                            }
                            SessionMessage::SwitchSession { session_id } => {
                                tracing::info!("SwitchSession: {}", session_id);

                                // Check if session exists
                                if !session_mgr.session_exists(&session_id).await {
                                    let mut send_lock = send_shared.lock().await;
                                    let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                        TerminalEvent::session_not_found(session_id.clone()),
                                    )).await;
                                    break;
                                }

                                // Phase 05: Stop pump task for previous session
                                if let Some(ref old_session_id) = active_session_id {
                                    tracing::info!("Stopping pump for previous session: {}", old_session_id);
                                    session_mgr.stop_pump_for_session(old_session_id).await;
                                }

                                // Get history buffer
                                let history = session_mgr.get_history(&session_id).await;

                                // Send history if available
                                if !history.is_empty() {
                                    let mut send_lock = send_shared.lock().await;
                                    let _ = Self::send_message(&mut *send_lock, &NetworkMessage::SessionHistory {
                                        session_id: session_id.clone(),
                                        lines: history,
                                    }).await;
                                }

                                // Update active session
                                active_session_id = Some(session_id.clone());

                                // Phase 05: Start TaggedOutput pump for new active session
                                if let Some(output_rx) = session_mgr.take_output_rx_for_session(&session_id).await {
                                    let history_tx = session_mgr.get_history_sender(&session_id).await;
                                    let session_key = session_id.clone();
                                    let send_clone = send_shared.clone();

                                    let pump_handle = tokio::spawn(async move {
                                        let mut send_lock = send_clone.lock().await;
                                        if let Err(e) = pump_pty_to_quic_tagged(
                                            // Convert Receiver to AsyncRead
                                            {
                                                let stream = tokio_stream::wrappers::ReceiverStream::new(output_rx)
                                                    .map(Ok::<_, std::io::Error>);
                                                tokio_util::io::StreamReader::new(stream)
                                            },
                                            &mut *send_lock,
                                            session_key.clone(),
                                            history_tx,
                                        ).await {
                                            tracing::error!("TaggedOutput pump error for session {}: {}", session_key, e);
                                        }
                                        tracing::debug!("TaggedOutput pump completed for session {}", session_key);
                                    });

                                    // Store pump handle
                                    session_mgr.set_pump_handle_for_session(&session_id, pump_handle).await;
                                    tracing::info!("TaggedOutput pump started for session {}", session_id);
                                } else {
                                    tracing::warn!("No PTY output receiver available for session {} (pump already started?)", session_id);
                                }

                                // Send SessionSwitched event
                                let mut send_lock = send_shared.lock().await;
                                let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                    TerminalEvent::session_switched(session_id.clone()),
                                )).await;

                                tracing::info!("Switched to active session: {}", session_id);
                            }
                            SessionMessage::CloseSession { session_id } => {
                                tracing::info!("CloseSession: {}", session_id);

                                match session_mgr.close_session(&session_id).await {
                                    Ok(()) => {
                                        // Send SessionClosed event
                                        let mut send_lock = send_shared.lock().await;
                                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                            TerminalEvent::session_closed(session_id.clone()),
                                        )).await;

                                        // Clear active session if it was the closed one
                                        if active_session_id.as_ref() == Some(&session_id) {
                                            active_session_id = None;
                                        }

                                        tracing::info!("Session {} closed", session_id);
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to close session {}: {}", session_id, e);
                                        let mut send_lock = send_shared.lock().await;
                                        let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                            TerminalEvent::Error { message: format!("Failed to close session: {}", e) },
                                        )).await;
                                    }
                                }
                            }
                            SessionMessage::ListSessions => {
                                tracing::info!("ListSessions requested");

                                let sessions = session_mgr.list_uuid_sessions().await;
                                let response_text = format!("Active sessions:\n{}", sessions.join("\n"));

                                let mut send_lock = send_shared.lock().await;
                                let _ = Self::send_message(&mut *send_lock, &NetworkMessage::Event(
                                    TerminalEvent::Output { data: response_text.into_bytes() },
                                )).await;
                            }
                        }
                    }
                    _ => {
                        tracing::warn!("Unhandled message type");
                    }
                }
            }
        }

        // Cleanup session on disconnect
        if let Some(id) = session_id {
            let _ = session_mgr.cleanup_session(id).await;
        }

        // Wait for PTY pump task to complete
        if let Some(task) = pty_task {
            let _ = tokio::time::timeout(Duration::from_secs(2), task).await;
        }

        Ok(())
    }

    /// Spawn session with terminal configuration
    ///
    /// Shared helper for Input and Command message handlers.
    /// Creates PTY session, applies resize, spawns output pump task.
    async fn spawn_session_with_config(
        session_mgr: &Arc<SessionManager>,
        pending_resize: Option<(u16, u16)>,
        pty_task: &mut Option<tokio::task::JoinHandle<()>>,
        session_id: &mut Option<u64>,
        send_shared: &Arc<Mutex<quinn::SendStream>>,
        initial_data: &[u8],
    ) -> Result<()> {
        let mut config = comacode_core::terminal::TerminalConfig::default();

        // Apply terminal size from earlier Resize message
        if let Some((rows, cols)) = pending_resize {
            config.rows = rows;
            config.cols = cols;
            // Env vars: Zsh reads COLUMNS/LINES before querying PTY driver
            config.env.push(("COLUMNS".to_string(), cols.to_string()));
            config.env.push(("LINES".to_string(), rows.to_string()));
            // Hide % marker if Zsh thinks line is incomplete
            config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
        }

        match session_mgr.create_session(config).await {
            Ok(id) => {
                *session_id = Some(id);
                tracing::info!("Created session {} for connection", id);

                // Resize PTY to match terminal size
                // This syncs the PTY driver with env vars
                if let Some((rows, cols)) = pending_resize {
                    tracing::info!("Resize PTY: {}x{}", rows, cols);
                    let _ = session_mgr.resize_session(id, rows, cols).await;
                }

                // Spawn PTY->QUIC pump task
                if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                    let send_clone = send_shared.clone();
                    *pty_task = Some(tokio::spawn(async move {
                        let mut send_lock = send_clone.lock().await;
                        if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
                            tracing::error!("PTY->QUIC pump error: {}", e);
                        }
                        tracing::debug!("PTY->QUIC pump completed");
                    }));
                    tracing::info!("PTY->QUIC pump task spawned for session {}", id);
                } else {
                    tracing::warn!("Failed to get PTY reader for session {}", id);
                }

                // Write initial data if non-empty
                if !initial_data.is_empty() {
                    let _ = session_mgr.write_to_session(id, initial_data).await;
                }

                Ok(())
            }
            Err(e) => {
                tracing::error!("Failed to create session: {}", e);
                Err(e)
            }
        }
    }

    /// Send message to stream
    async fn send_message(
        send: &mut quinn::SendStream,
        msg: &NetworkMessage,
    ) -> Result<()> {
        let encoded = MessageCodec::encode(msg)?;
        send.write_all(&encoded).await?;
        Ok(())
    }

    /// Try to decode a message from buffer
    ///
    /// Returns Some((message, remaining_bytes)) if successful
    /// Returns None if buffer is incomplete
    fn try_decode_message(buf: &[u8]) -> Option<(NetworkMessage, &[u8])> {
        if buf.len() < 4 {
            return None;
        }

        let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

        // Validate size (prevent DoS)
        if len > 16 * 1024 * 1024 {
            tracing::error!("Message too large: {} bytes", len);
            return None;
        }

        if buf.len() < 4 + len {
            // Incomplete message
            return None;
        }

        let msg_buf = &buf[..4 + len];
        let remaining = &buf[4 + len..];

        match MessageCodec::decode(msg_buf) {
            Ok(msg) => Some((msg, remaining)),
            Err(e) => {
                tracing::error!("Failed to decode message: {}", e);
                // Skip this message and continue
                Some((NetworkMessage::Close, remaining))
            }
        }
    }

    /// Get session manager reference
    #[allow(dead_code)]
    pub fn session_manager(&self) -> Arc<SessionManager> {
        Arc::clone(&self.session_mgr)
    }

    /// Shutdown server
    #[allow(dead_code)]
    pub async fn shutdown(self) -> Result<()> {
        if let Some(tx) = self.shutdown_tx {
            let _ = tx.send(());
        }
        self.endpoint.close(0u32.into(), b"Server shutdown");
        Ok(())
    }
}

/// Generate self-signed TLS certificate with keypair
fn generate_cert_with_keypair() -> Result<(CertificateDer<'static>, KeyPair)> {
    use rcgen;

    // Simple self-signed certificate generation
    let cert = rcgen::generate_simple_self_signed(vec!["Comacode".to_string()])
        .context("Failed to generate certificate")?;

    Ok((
        CertificateDer::from(cert.cert.der().to_vec()),
        cert.key_pair,
    ))
}
