//! QUIC server for terminal connections
//!
//! Provides encrypted QUIC endpoint for mobile client connections.

use anyhow::{Context, Result};
use comacode_core::{
    protocol::MessageCodec,
    transport::configure_server,
    types::{NetworkMessage, SessionMessage, TerminalEvent},
};
use quinn::{Endpoint, TokioRuntime};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};
use tokio_stream::StreamExt;
use rcgen::KeyPair;

use crate::auth::TokenStore;
use crate::ratelimit::RateLimiterStore;
use crate::session::SessionManager;
use crate::vfs;
use crate::vfs_watcher::WatcherManager;

/// Global connection ID counter
static NEXT_CONNECTION_ID: AtomicU64 = AtomicU64::new(1);

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
        let mut last_resize: Option<(u16, u16)> = None; // Track last applied resize to skip redundant SIGWINCH

        // Generate unique connection ID for this connection
        let connection_id = NEXT_CONNECTION_ID.fetch_add(1, Ordering::SeqCst);
        tracing::info!("New connection {} from {}", connection_id, peer_addr);

        // Channel-based writer: avoids deadlock where pump holds send lock forever.
        // All writers (pump + main loop) encode → send bytes into channel.
        // Single writer task owns SendStream, drains channel, writes to QUIC.
        let (send_tx, send_rx) = mpsc::channel::<Vec<u8>>(256);
        let _writer_task = tokio::spawn(async move {
            let mut send = send;
            let mut rx = send_rx;
            while let Some(bytes) = rx.recv().await {
                if let Err(e) = send.write_all(&bytes).await {
                    tracing::error!("QUIC writer error: {}", e);
                    break;
                }
            }
            tracing::debug!("QUIC writer task completed");
        });

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
            tracing::info!("🟣 [BACKEND RECV] Received {} bytes, buffer_size={}, raw_chunk={:?}",
                n, recv_buffer.len(), &read_buf[..n.min(64)]);

            // Process all complete messages in buffer
            while let Some((msg, remaining)) = Self::try_decode_message(&recv_buffer) {
                let remaining_len = remaining.len();
                recv_buffer = remaining.to_vec();

                tracing::info!("🟣 [BACKEND DECODE] Received message: {:?}, remaining_buffer={} bytes",
                    std::mem::discriminant(&msg), remaining_len);

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
                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::hello(None)) {
                            let _ = send_tx.send(encoded).await;
                        }
                        break;
                    }

                    // Reset auth failures on success
                    rate_limiter.reset_auth_failures(peer_addr.ip()).await;
                    authenticated = true;
                    tracing::info!("Client authenticated: {}", peer_addr);

                    // Validate protocol version
                    if let Err(e) = msg.validate_handshake() {
                        tracing::error!("Handshake validation failed: {}", e);
                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::hello(None)) {
                            let _ = send_tx.send(encoded).await;
                        }
                        break;
                    }

                    // Respond with Hello
                    let encoded = MessageCodec::encode(&NetworkMessage::hello(None))?;
                    send_tx.send(encoded).await.map_err(|e| anyhow::anyhow!("send failed: {}", e))?;
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
                            &send_tx,
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
                            &send_tx,
                            cmd.text.as_bytes(),
                        ).await;
                    }
                    }
                    NetworkMessage::KeyBatch { keys, sequence_num, timestamp_ms } => {
                    // SSH Terminal Mode - Phase 1: Batched keystrokes
                    tracing::info!("🟣 [BACKEND HANDLER] KeyBatch received: seq={}, {} bytes, keys={:?}, active_session={:?}, session_id={:?}",
                        sequence_num, keys.len(), keys, active_session_id, session_id);

                    if !authenticated {
                        tracing::warn!("KeyBatch received before authentication from {}", peer_addr);
                        break;
                    }

                    // Calculate and log latency for monitoring
                    let now_ms = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or(0);
                    let client_to_server_latency = now_ms.saturating_sub(timestamp_ms);
                    tracing::info!(
                        "KeyBatch: seq={}, latency={}ms, {} bytes",
                        sequence_num,
                        client_to_server_latency,
                        keys.len()
                    );

                    // Write to active session (UUID or legacy)
                    if let Some(ref uuid) = active_session_id {
                        tracing::info!("Writing to UUID session: {}", uuid);
                        if let Err(e) = session_mgr.write_to_uuid_session(uuid, &keys).await {
                            tracing::error!("KeyBatch write failed for UUID session {}: {}", uuid, e);
                        } else {
                            tracing::info!("KeyBatch written to UUID session {} successfully", uuid);
                        }
                    } else if let Some(id) = session_id {
                        tracing::info!("Writing to legacy session: {}", id);
                        if let Err(e) = session_mgr.write_to_session(id, &keys).await {
                            tracing::error!("KeyBatch write failed for PTY: {}", e);
                        } else {
                            tracing::info!("KeyBatch written to legacy session {} successfully", id);
                        }
                    } else {
                        // No active session - spawn new one with first keystroke
                        tracing::warn!("No active session - spawning with KeyBatch data");
                        let _ = Self::spawn_session_with_config(
                            &session_mgr,
                            pending_resize,
                            &mut pty_task,
                            &mut session_id,
                            &send_tx,
                            &keys,
                        ).await;
                    }

                    // Send ACK for prediction confirmation (Phase 2)
                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::KeyBatchAck { sequence_num }) {
                        let _ = send_tx.send(encoded).await;
                        tracing::info!("KeyBatchAck sent for seq={}", sequence_num);
                    }
                    }
                    NetworkMessage::Ping { timestamp } => {
                    // Respond with Pong
                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::pong(timestamp)) {
                        let _ = send_tx.send(encoded).await;
                    }
                    }
                    NetworkMessage::Resize { rows, cols } => {
                    // Skip redundant resize — PTY already has this size
                    // Prevents unnecessary SIGWINCH → shell re-rendering prompt
                    if last_resize == Some((rows, cols)) {
                        tracing::debug!("Skipping redundant resize {}x{}", rows, cols);
                    } else if let Some(ref uuid) = active_session_id {
                        if let Err(e) = session_mgr.resize_uuid_session(uuid, rows, cols).await {
                            tracing::error!("Failed to resize UUID session {}: {}", uuid, e);
                        }
                        last_resize = Some((rows, cols));
                    } else if let Some(id) = session_id {
                        if let Err(e) = session_mgr.resize_session(id, rows, cols).await {
                            tracing::error!("Failed to resize PTY: {}", e);
                        }
                        last_resize = Some((rows, cols));
                    } else {
                        // Store pending resize for when session is created
                        pending_resize = Some((rows, cols));
                        last_resize = Some((rows, cols));
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
                            if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                comacode_core::types::TerminalEvent::Error { message: error_msg }
                            )) {
                                let _ = send_tx.send(encoded).await;
                            }
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
                                    if let Ok(encoded) = MessageCodec::encode(&msg) {
                                        if send_tx.send(encoded).await.is_err() {
                                            tracing::error!("Failed to send DirChunk: channel closed");
                                            break;
                                        }
                                    }
                                }

                                tracing::info!("ListDir completed: {} chunks sent", total);
                            }
                            Err(e) => {
                                let error_msg = format!("Failed to read directory: {}", e);
                                tracing::error!("{}", error_msg);
                                if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                    comacode_core::types::TerminalEvent::Error { message: error_msg }
                                )) {
                                    let _ = send_tx.send(encoded).await;
                                }
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
                            if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::WatchError {
                                watcher_id: format!("watch_{}", session_id.unwrap_or(0)),
                                error: error_msg,
                            }) {
                                let _ = send_tx.send(encoded).await;
                            }
                            break;
                        }

                        if !path_buf.is_dir() {
                            let error_msg = format!("Path is not a directory: {}", path);
                            tracing::warn!("{}", error_msg);
                            if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::WatchError {
                                watcher_id: format!("watch_{}", session_id.unwrap_or(0)),
                                error: error_msg,
                            }) {
                                let _ = send_tx.send(encoded).await;
                            }
                            break;
                        }

                        // Start watching
                        let watcher_id = format!("watch_{}", session_id.unwrap_or(0));
                        let watcher_mgr_clone: Arc<WatcherManager> = Arc::clone(&watcher_mgr);
                        let send_clone = send_tx.clone();

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

                                let tx = send_clone.clone();
                                tokio::spawn(async move {
                                    if let Ok(encoded) = MessageCodec::encode(&msg) {
                                        let _ = tx.send(encoded).await;
                                    }
                                });
                            },
                        ).await {
                            tracing::error!("Failed to start watcher: {}", e);
                            if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::WatchError {
                                watcher_id: watcher_id.clone(),
                                error: format!("Failed to start watcher: {}", e),
                            }) {
                                let _ = send_tx.send(encoded).await;
                            }
                            break;
                        }

                        // Send WatchStarted confirmation
                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::WatchStarted {
                            watcher_id,
                        }) {
                            let _ = send_tx.send(encoded).await;
                        }
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

                        // Security: Validate path is within user's home directory
                        // Use home_dir as allowed_base (user can access their own files)
                        // Falls back to "/" if home_dir unavailable (allows all paths)
                        let home_dir = dirs::home_dir()
                            .unwrap_or_else(|| PathBuf::from("/"));

                        if let Err(e) = crate::vfs::validate_path(&path_buf, &home_dir) {
                            tracing::warn!("ReadFile path validation failed: {}", e);
                            let response = NetworkMessage::FileContent {
                                path: path.clone(),
                                content: String::new(),
                                size: 0,
                                truncated: false,
                            };
                            if let Ok(encoded) = MessageCodec::encode(&response) {
                                let _ = send_tx.send(encoded).await;
                            }
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

                        if let Ok(encoded) = MessageCodec::encode(&response) {
                            let _ = send_tx.send(encoded).await;
                        }
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

                                // Idempotent: if session already exists, just activate it
                                // Prevents PTY re-spawn → no duplicate prompt on session switch
                                if session_mgr.session_exists(&session_id).await {
                                    tracing::info!("CreateSession: session {} already exists, activating (idempotent)", session_id);

                                    active_session_id = Some(session_id.clone());
                                    pending_resize = None;

                                    // Check if pump is still running FOR THIS CONNECTION
                                    // - Pump running for THIS connection → session switch, skip respawn
                                    // - Pump running for DIFFERENT connection → stale, need respawn
                                    // - Pump not running → connection died, need respawn
                                    let pump_for_this_connection = session_mgr.is_pump_for_connection(&session_id, connection_id).await;

                                    if pump_for_this_connection {
                                        // Same connection, session switch - NO respawn needed
                                        // Pump is still sending to current send_tx
                                        tracing::info!("Session {} pump running for connection {}, reactivating without respawn", session_id, connection_id);
                                    } else {
                                        // Either: pump dead, or pump running for different connection
                                        // In both cases, need to stop old pump and respawn PTY
                                        tracing::info!("Session {} needs respawn (pump not for connection {})", session_id, connection_id);

                                        // Stop any stale/zombie pump handle
                                        session_mgr.stop_pump_for_session(&session_id).await;

                                        // Respawn PTY to get fresh output channel
                                        let output_rx = match session_mgr.respawn_pty_for_session(&session_id).await {
                                            Ok(rx) => Some(rx),
                                            Err(e) => {
                                                tracing::error!("Failed to respawn PTY for session {}: {}", session_id, e);
                                                None
                                            }
                                        };

                                        // Start new pump with THIS connection's send_tx
                                        if let Some(output_rx) = output_rx {
                                            let history_tx = session_mgr.get_history_sender(&session_id).await;
                                            let session_key = session_id.clone();
                                            let pump_tx = send_tx.clone();

                                            let pump_handle = tokio::spawn(async move {
                                                Self::pump_tagged_via_channel(output_rx, pump_tx, session_key.clone(), history_tx).await;
                                            });

                                            session_mgr.set_pump_handle_for_session(&session_id, pump_handle, connection_id).await;
                                            tracing::info!("TaggedOutput pump restarted for session {} with connection {}", session_id, connection_id);
                                        } else {
                                            tracing::error!("No output_rx available for session {} after respawn - terminal will be dead", session_id);
                                        }
                                    }

                                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                        TerminalEvent::session_created(session_id.clone()),
                                    )) {
                                        let _ = send_tx.send(encoded).await;
                                    }
                                } else {
                                // --- Normal path: session does not exist, create new PTY ---

                                let path_buf = PathBuf::from(&project_path);
                                if !path_buf.exists() {
                                    let error_msg = format!("Project path not found: {}", project_path);
                                    tracing::warn!("{}", error_msg);
                                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                        TerminalEvent::Error { message: error_msg },
                                    )) {
                                        let _ = send_tx.send(encoded).await;
                                    }
                                    break;
                                }

                                let mut config = comacode_core::terminal::TerminalConfig::default();
                                if let Some((rows, cols)) = pending_resize {
                                    config.rows = rows;
                                    config.cols = cols;
                                    config.env.push(("COLUMNS".to_string(), cols.to_string()));
                                    config.env.push(("LINES".to_string(), rows.to_string()));
                                }

                                match session_mgr.create_session_with_uuid(
                                    session_id.clone(),
                                    config,
                                    &project_path,
                                ).await {
                                    Ok(()) => {
                                        active_session_id = Some(session_id.clone());
                                        // PTY already spawned with pending_resize size — record as last applied
                                        last_resize = pending_resize;

                                        // Start TaggedOutput pump via channel (no lock held)
                                        if let Some(output_rx) = session_mgr.take_output_rx_for_session(&session_id).await {
                                            let history_tx = session_mgr.get_history_sender(&session_id).await;
                                            let session_key = session_id.clone();
                                            let pump_tx = send_tx.clone();

                                            let pump_handle = tokio::spawn(async move {
                                                Self::pump_tagged_via_channel(output_rx, pump_tx, session_key.clone(), history_tx).await;
                                            });

                                            session_mgr.set_pump_handle_for_session(&session_id, pump_handle, connection_id).await;
                                            tracing::info!("TaggedOutput pump started for newly created session {}", session_id);
                                        }

                                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                            TerminalEvent::session_created(session_id.clone()),
                                        )) {
                                            let _ = send_tx.send(encoded).await;
                                        }

                                        tracing::info!("Session {} created and activated for project {}", session_id, project_path);
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to create session {}: {}", session_id, e);
                                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                            TerminalEvent::Error { message: format!("Failed to create session: {}", e) },
                                        )) {
                                            let _ = send_tx.send(encoded).await;
                                        }
                                    }
                                }
                                } // end else: normal CreateSession path
                            }
                            SessionMessage::CheckSession { session_id } => {
                                tracing::info!("CheckSession: {}", session_id);

                                let exists = session_mgr.session_exists(&session_id).await;
                                let event = if exists {
                                    TerminalEvent::session_reattach(session_id.clone())
                                } else {
                                    TerminalEvent::session_not_found(session_id.clone())
                                };

                                if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(event)) {
                                    let _ = send_tx.send(encoded).await;
                                }
                            }
                            SessionMessage::SwitchSession { session_id } => {
                                tracing::info!("SwitchSession: {}", session_id);

                                if !session_mgr.session_exists(&session_id).await {
                                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                        TerminalEvent::session_not_found(session_id.clone()),
                                    )) {
                                        let _ = send_tx.send(encoded).await;
                                    }
                                    break;
                                }

                                if let Some(ref old_session_id) = active_session_id {
                                    tracing::info!("Stopping pump for previous session: {}", old_session_id);
                                    session_mgr.stop_pump_for_session(old_session_id).await;
                                }

                                let history = session_mgr.get_history(&session_id).await;
                                if !history.is_empty() {
                                    if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::SessionHistory {
                                        session_id: session_id.clone(),
                                        lines: history,
                                    }) {
                                        let _ = send_tx.send(encoded).await;
                                    }
                                }

                                active_session_id = Some(session_id.clone());

                                if let Some(output_rx) = session_mgr.take_output_rx_for_session(&session_id).await {
                                    let history_tx = session_mgr.get_history_sender(&session_id).await;
                                    let session_key = session_id.clone();
                                    let pump_tx = send_tx.clone();

                                    let pump_handle = tokio::spawn(async move {
                                        Self::pump_tagged_via_channel(output_rx, pump_tx, session_key.clone(), history_tx).await;
                                    });

                                    session_mgr.set_pump_handle_for_session(&session_id, pump_handle, connection_id).await;
                                    tracing::info!("TaggedOutput pump started for session {}", session_id);
                                } else {
                                    tracing::warn!("No PTY output receiver available for session {} (pump already started?)", session_id);
                                }

                                if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                    TerminalEvent::session_switched(session_id.clone()),
                                )) {
                                    let _ = send_tx.send(encoded).await;
                                }

                                tracing::info!("Switched to active session: {}", session_id);
                            }
                            SessionMessage::CloseSession { session_id } => {
                                tracing::info!("CloseSession: {}", session_id);

                                match session_mgr.close_session(&session_id).await {
                                    Ok(()) => {
                                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                            TerminalEvent::session_closed(session_id.clone()),
                                        )) {
                                            let _ = send_tx.send(encoded).await;
                                        }

                                        if active_session_id.as_ref() == Some(&session_id) {
                                            active_session_id = None;
                                        }
                                        tracing::info!("Session {} closed", session_id);
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to close session {}: {}", session_id, e);
                                        if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                            TerminalEvent::Error { message: format!("Failed to close session: {}", e) },
                                        )) {
                                            let _ = send_tx.send(encoded).await;
                                        }
                                    }
                                }
                            }
                            SessionMessage::ListSessions => {
                                tracing::info!("ListSessions requested");

                                let sessions = session_mgr.list_uuid_sessions().await;
                                let response_text = format!("Active sessions:\n{}", sessions.join("\n"));

                                if let Ok(encoded) = MessageCodec::encode(&NetworkMessage::Event(
                                    TerminalEvent::Output { data: response_text.into_bytes() },
                                )) {
                                    let _ = send_tx.send(encoded).await;
                                }
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
        send_tx: &mpsc::Sender<Vec<u8>>,
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

                // Spawn PTY->QUIC pump task via channel
                if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                    let pump_tx = send_tx.clone();
                    *pty_task = Some(tokio::spawn(async move {
                        let mut buf = vec![0u8; 8192];
                        let mut pty = pty_reader;
                        loop {
                            match tokio::io::AsyncReadExt::read(&mut pty, &mut buf).await {
                                Ok(0) => break,
                                Ok(n) => {
                                    let msg = NetworkMessage::Event(comacode_core::types::TerminalEvent::Output {
                                        data: buf[..n].to_vec()
                                    });
                                    if let Ok(encoded) = MessageCodec::encode(&msg) {
                                        if pump_tx.send(encoded).await.is_err() { break; }
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("PTY->QUIC pump error: {}", e);
                                    break;
                                }
                            }
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

    /// Pump PTY output via channel (no SendStream lock held)
    ///
    /// Reads from PTY output receiver, encodes as TaggedOutput, sends via channel.
    /// Also captures history lines for inactive session replay.
    async fn pump_tagged_via_channel(
        output_rx: tokio::sync::mpsc::Receiver<bytes::Bytes>,
        send_tx: mpsc::Sender<Vec<u8>>,
        session_id: String,
        history_tx: Option<tokio::sync::mpsc::Sender<String>>,
    ) {
        let mut output_rx = output_rx;
        let mut line_accumulator = Vec::new();

        while let Some(chunk) = output_rx.recv().await {
            let data: &[u8] = &chunk;
            tracing::info!("[PTY->QUIC] Read {} bytes for session {}", data.len(), session_id);

            let msg = NetworkMessage::TaggedOutput(comacode_core::types::TaggedOutput {
                session_id: session_id.clone(),
                data: data.to_vec(),
            });
            if let Ok(encoded) = MessageCodec::encode(&msg) {
                if send_tx.send(encoded).await.is_err() {
                    tracing::error!("TaggedOutput pump: channel closed for session {}", session_id);
                    break;
                }
            }

            // History capture (best effort)
            if let Some(ref tx) = history_tx {
                line_accumulator.extend_from_slice(data);
                if let Ok(text) = String::from_utf8(line_accumulator.clone()) {
                    let mut split_lines = text.split('\n').peekable();
                    let mut has_incomplete = false;
                    while let Some(line) = split_lines.next() {
                        if split_lines.peek().is_some() {
                            let _ = tx.try_send(line.to_string());
                        } else if !text.ends_with('\n') && !line.is_empty() {
                            line_accumulator = line.as_bytes().to_vec();
                            has_incomplete = true;
                        }
                    }
                    if !has_incomplete {
                        line_accumulator.clear();
                    }
                } else if line_accumulator.len() > 10000 {
                    line_accumulator.clear();
                }
            }
        }
        tracing::debug!("TaggedOutput pump completed for session {}", session_id);
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
