//! Comacode Host Agent
//!
//! Standalone PC binary that manages PTY sessions and exposes them via QUIC server.
//!
//! Desktop-only - not available on iOS.

#![cfg(not(target_os = "ios"))]

mod auth;
mod cert;
mod pty;
mod quic_server;
mod ratelimit;
mod session;
mod snapshot;
mod vfs;
mod web_ui;

use anyhow::{Context, Result};
use clap::Parser;
use comacode_core::{CoreError, QrPayload};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use tokio::signal;
use tracing::{error, info, warn, Level};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

use crate::auth::TokenStore;
use crate::ratelimit::RateLimiterStore;
use std::sync::Arc;

/// Comacode Host Agent - Terminal server for mobile clients
#[derive(Parser, Debug)]
#[command(name = "hostagent")]
#[command(author = "Comacode Team")]
#[command(version = env!("CARGO_PKG_VERSION"))]
#[command(about = "Host agent for Comacode remote terminal", long_about = None)]
struct Args {
    /// Bind address for QUIC server
    #[arg(short, long, default_value = "0.0.0.0:8443")]
    bind: String,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, default_value = "info")]
    log_level: String,

    /// Disable browser auto-open (for web UI)
    #[arg(long, default_value = "false")]
    no_browser: bool,

    /// Use terminal QR instead of web dashboard
    #[arg(long, default_value = "false")]
    qr_terminal: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize rustls CryptoProvider with ring backend (required for rustls 0.23+)
    let _ = rustls::crypto::ring::default_provider().install_default();

    let args = Args::parse();

    // Setup logging
    setup_logging(&args.log_level)?;

    info!("Starting Comacode Host Agent v{}", env!("CARGO_PKG_VERSION"));

    // Parse bind address
    let bind_addr: SocketAddr = args
        .bind
        .parse()
        .with_context(|| format!("Invalid bind address: {}", args.bind))?;

    info!("Starting QUIC server on {}", bind_addr);

    // Generate auth token for QR pairing
    let token_store = Arc::new(TokenStore::new());
    let token = token_store.generate_token().await;
    info!("Auth token: {}", token.to_hex());

    // Create rate limiter for auth failure tracking
    let rate_limiter = Arc::new(RateLimiterStore::new());

    // Create and run QUIC server with auth stores
    let (mut server, cert, _key) = quic_server::QuicServer::new(bind_addr, token_store, rate_limiter).await?;

    // Get certificate fingerprint for QR code
    let cert_fingerprint = crate::cert::CertStore::fingerprint_from_cert_der(&cert);
    info!("Certificate fingerprint: {}", cert_fingerprint);

    // Get local IP for QR code
    let local_ip = get_local_ip()?;
    info!("Local IP: {}", local_ip);

    // Get actual port from server (may be different if binding to :0)
    let mut actual_port = bind_addr.port();
    if actual_port == 0 {
        // If binding to :0, OS assigns port - need to get it from server
        // For now, use default 8443
        actual_port = 8443;
    }

    // Create QR payload
    let qr_payload = QrPayload::new(
        local_ip.to_string(),
        actual_port,
        cert_fingerprint.clone(),
        token.to_hex(),
    );

    // Level 2: Web Dashboard (default)
    if !args.qr_terminal {
        // Create web server
        let web_server = web_ui::WebServer::new();
        let web_state = web_server.state();

        // Set QR payload for web UI
        web_state.set_qr_payload(qr_payload.clone()).await;

        // Start web server (binds to 127.0.0.1 only)
        let web_addr = web_server.start().await
            .context("Failed to start web server")?;

        info!("Web dashboard available at http://{}", web_addr);

        // Open browser if not disabled
        if !args.no_browser {
            let url = format!("http://{}", web_addr);
            if let Err(e) = web_ui::WebServer::open_browser(&url) {
                warn!("Failed to open browser: {}", e);
                println!("Open this URL in your browser: {}", url);
            }
        }

        println!("============================================");
        println!("Web Dashboard: http://{}", web_addr);
        println!("Scan QR code in browser to connect");
        println!("============================================");
    } else {
        // Level 1: Terminal QR (legacy)
        display_qr_code(&local_ip, actual_port, &cert_fingerprint, &token.to_hex());
    }

    // Spawn server task
    let server_handle = tokio::spawn(async move {
        if let Err(e) = server.run().await {
            error!("Server error: {}", e);
        }
    });

    // Wait for shutdown signal
    let mut sigterm = tokio::signal::unix::signal(signal::unix::SignalKind::terminate())
        .expect("Failed to setup SIGTERM handler");

    tokio::select! {
        _ = signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down...");
        }
        _ = sigterm.recv() => {
            info!("Received SIGTERM, shutting down...");
        }
        result = server_handle => {
            result.context("Server task failed")?;
        }
    }

    info!("Shutdown complete");
    Ok(())
}

/// Setup logging with tracing
fn setup_logging(level: &str) -> Result<()> {
    let log_level = level
        .parse::<Level>()
        .unwrap_or(Level::INFO);

    let filter = EnvFilter::builder()
        .with_default_directive(log_level.into())
        .from_env_lossy();

    tracing_subscriber::registry()
        .with(filter)
        .with(fmt::layer().with_writer(std::io::stderr))
        .init();

    Ok(())
}

/// Get local IP address for QR code
///
/// **IMPORTANT**: Filters out Docker bridge (172.17.x.x), loopback (127.x.x.x)
/// and falls back to 192.168.1.1 for typical LAN.
fn get_local_ip() -> Result<IpAddr> {
    use std::net::UdpSocket;

    // Create UDP socket to a non-local address (doesn't actually send data)
    let socket = UdpSocket::bind("0.0.0.0:0")
        .map_err(|e| CoreError::NetworkError(e.to_string()))?;

    // Connect to external DNS (doesn't send, just determines local interface)
    socket.connect("8.8.8.8:80")
        .map_err(|e| CoreError::NetworkError(e.to_string()))?;

    let local_ip = socket.local_addr()?.ip();

    // Filter: reject Docker bridge (172.17.x.x), loopback
    match local_ip {
        IpAddr::V4(ipv4) if is_docker_or_loopback(ipv4) => {
            warn!("Detected Docker/loopback IP {}, falling back to 192.168.1.1", local_ip);
            // Fallback: assume typical LAN
            Ok(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1)))
        }
        _ => Ok(local_ip),
    }
}

/// Check if IP is Docker bridge or loopback
fn is_docker_or_loopback(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    // Docker bridge: 172.17.x.x
    // Loopback: 127.x.x.x
    octets[0] == 172 && octets[1] == 17
        || octets[0] == 127
}

/// Display QR code for mobile pairing
fn display_qr_code(ip: &IpAddr, port: u16, fingerprint: &str, token: &str) {
    let qr_payload = QrPayload::new(
        ip.to_string(),
        port,
        fingerprint.to_string(),
        token.to_string(),
    );

    println!("============================================");
    println!("Scan QR code to connect:");
    println!();

    match qr_payload.to_qr_terminal() {
        Ok(qr) => println!("{}", qr),
        Err(e) => {
            warn!("Failed to generate QR code: {}", e);
            println!("QR code generation failed - see logs");
        }
    }

    println!();
    println!("============================================");
    println!("IP: {}", qr_payload.ip);
    println!("Port: {}", qr_payload.port);
    println!("Fingerprint: {}", qr_payload.fingerprint);
    println!("============================================");
    println!("TIP: If QR doesn't work, check IP with 'ifconfig' or 'ip addr'");
}
