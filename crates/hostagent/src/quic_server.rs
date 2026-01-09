//! QUIC server for terminal connections
//!
//! Provides encrypted QUIC endpoint for mobile client connections.

use anyhow::{Context, Result};
use comacode_core::{
    protocol::MessageCodec,
    transport::{configure_server, stream::pump_pty_to_quic},
    types::NetworkMessage,
};
use quinn::{Endpoint, TokioRuntime};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{oneshot, Mutex};
use rcgen::KeyPair;

use crate::auth::TokenStore;
use crate::ratelimit::RateLimiterStore;
use crate::session::SessionManager;

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
                            tokio::spawn(async move {
                                if let Err(e) = Self::handle_connection(incoming, session_mgr, token_store, rate_limiter).await {
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
                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_stream(send, recv, session_mgr, token_store, rate_limiter, remote_addr).await {
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
        mut send: quinn::SendStream,
        mut recv: quinn::RecvStream,
        session_mgr: Arc<SessionManager>,
        token_store: Arc<TokenStore>,
        rate_limiter: Arc<RateLimiterStore>,
        peer_addr: SocketAddr,
    ) -> Result<()> {
        let mut session_id: Option<u64> = None;
        let mut authenticated = false;
        let mut pty_task: Option<tokio::task::JoinHandle<()>> = None;
        let mut pending_resize: Option<(u16, u16)> = None; // Store (rows, cols) before session created

        // Share send stream for PTY output forwarding
        let send_shared = Arc::new(Mutex::new(send));

        // Message receive loop
        let mut read_buf = vec![0u8; 1024];

        loop {
            // Read from stream
            match recv.read(&mut read_buf).await? {
                Some(n) if n > 0 => {
                    // Parse message
                    let msg = match MessageCodec::decode(&read_buf[..n]) {
                        Ok(msg) => msg,
                        Err(e) => {
                            tracing::error!("Failed to decode message: {}", e);
                            continue;
                        }
                    };

                    tracing::debug!("Received message: {:?}", std::mem::discriminant(&msg));

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

                            if let Some(id) = session_id {
                                // Write raw bytes directly to PTY
                                if let Err(e) = session_mgr.write_to_session(id, &data).await {
                                    tracing::error!("Failed to write input to PTY: {}", e);
                                }
                            } else {
                                // Spawn new session with terminal configuration
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
                                        session_id = Some(id);
                                        tracing::info!("Created session {} for connection", id);

                                        // Resize PTY to match terminal size
                                        // This syncs the PTY driver with env vars
                                        if let Some((rows, cols)) = pending_resize {
                                            tracing::info!("Resize PTY: {}x{}", rows, cols);
                                            let _ = session_mgr.resize_session(id, rows, cols).await;
                                        }

                                        // Spawn PTY→QUIC pump task
                                        if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                                            let send_clone = send_shared.clone();
                                            pty_task = Some(tokio::spawn(async move {
                                                let mut send_lock = send_clone.lock().await;
                                                if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
                                                    tracing::error!("PTY→QUIC pump error: {}", e);
                                                }
                                                tracing::debug!("PTY→QUIC pump completed");
                                            }));
                                            tracing::info!("PTY→QUIC pump task spawned for session {}", id);
                                        } else {
                                            tracing::warn!("Failed to get PTY reader for session {}", id);
                                        }

                                        // Write initial data if non-empty
                                        // Empty Input = eager spawn trigger, don't write to PTY
                                        if !data.is_empty() {
                                            let _ = session_mgr.write_to_session(id, &data).await;
                                        }
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to create session: {}", e);
                                    }
                                }
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

                            // Forward command text to PTY
                            if let Some(id) = session_id {
                                if let Err(e) = session_mgr.write_to_session(id, cmd.text.as_bytes()).await {
                                    tracing::error!("Failed to write to PTY: {}", e);
                                }
                            } else {
                                // Spawn new session with terminal configuration (legacy Command path)
                                let mut config = comacode_core::terminal::TerminalConfig::default();

                                if let Some((rows, cols)) = pending_resize.take() {
                                    config.rows = rows;
                                    config.cols = cols;
                                    // Env vars: Zsh reads COLUMNS/LINES before querying PTY driver
                                    config.env.push(("COLUMNS".to_string(), cols.to_string()));
                                    config.env.push(("LINES".to_string(), rows.to_string()));
                                    config.env.push(("PROMPT_EOL_MARK".to_string(), "".to_string()));
                                }

                                match session_mgr.create_session(config).await {
                                    Ok(id) => {
                                        session_id = Some(id);
                                        tracing::info!("Created session {} for connection (legacy Command)", id);

                                        // Resize PTY to match terminal size
                                        if let Some((rows, cols)) = pending_resize {
                                            let _ = session_mgr.resize_session(id, rows, cols).await;
                                        }

                                        if let Some(pty_reader) = session_mgr.get_pty_reader(id).await {
                                            let send_clone = send_shared.clone();
                                            pty_task = Some(tokio::spawn(async move {
                                                let mut send_lock = send_clone.lock().await;
                                                if let Err(e) = pump_pty_to_quic(pty_reader, &mut *send_lock).await {
                                                    tracing::error!("PTY→QUIC pump error: {}", e);
                                                }
                                                tracing::debug!("PTY→QUIC pump completed");
                                            }));
                                            tracing::info!("PTY→QUIC pump task spawned for session {}", id);
                                        }

                                        // Forward command only if non-empty
                                        if !cmd.text.is_empty() {
                                            let _ = session_mgr.write_to_session(id, cmd.text.as_bytes()).await;
                                        }
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to create session: {}", e);
                                    }
                                }
                            }
                        }
                        NetworkMessage::Ping { timestamp } => {
                            // Respond with Pong
                            let response = NetworkMessage::pong(timestamp);
                            let mut send_lock = send_shared.lock().await;
                            Self::send_message(&mut *send_lock, &response).await?;
                        }
                        NetworkMessage::Resize { rows, cols } => {
                            if let Some(id) = session_id {
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
                        _ => {
                            tracing::warn!("Unhandled message type");
                        }
                    }
                }
                Some(0) | None => {
                    tracing::debug!("Stream closed by client");
                    break;
                }
                _ => {}
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

    /// Send message to stream
    async fn send_message(
        send: &mut quinn::SendStream,
        msg: &NetworkMessage,
    ) -> Result<()> {
        let encoded = MessageCodec::encode(msg)?;
        send.write_all(&encoded).await?;
        Ok(())
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
