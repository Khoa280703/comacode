//! Web UI Module for Comacode Host Agent
//!
//! Level 2: Localhost Web Dashboard
//! - QR code pairing page (Catppuccin Mocha theme)
//! - Real-time connection status via SSE
//! - Browser auto-open on startup
//!
//! # SECURITY
//! Web server MUST bind to 127.0.0.1 only (loopback).
//! Never bind to 0.0.0.0 to prevent LAN access to auth tokens.

use anyhow::{Context, Result};
use axum::{
    extract::State,
    response::sse::{Event, Sse},
    response::Html,
};
use comacode_core::QrPayload;
use futures::Stream;
use qrcode_generator::QrCodeEcc;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{info, warn};

/// Web bind address - MUST be loopback only for security
const WEB_BIND_ADDR: &str = "127.0.0.1:3721";

/// Connection status for SSE broadcasting
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionStatus {
    Waiting,
    Connected { peer: String, session_id: u64 },
    Disconnected,
}

impl ConnectionStatus {
    fn class(&self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Connected { .. } => "connected",
            Self::Disconnected => "disconnected",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::Waiting => "Waiting for connection...".to_string(),
            Self::Connected { peer, .. } => format!("Connected to {}", peer),
            Self::Disconnected => "Disconnected".to_string(),
        }
    }
}

/// State shared across web server
#[derive(Clone)]
pub struct WebState {
    status: Arc<Mutex<ConnectionStatus>>,
    qr_payload: Arc<Mutex<Option<QrPayload>>>,
}

impl WebState {
    pub fn new() -> Self {
        Self {
            status: Arc::new(Mutex::new(ConnectionStatus::Waiting)),
            qr_payload: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn set_qr_payload(&self, payload: QrPayload) {
        *self.qr_payload.lock().await = Some(payload);
    }

    #[allow(dead_code)]
    pub async fn update_status(&self, status: ConnectionStatus) {
        *self.status.lock().await = status;
    }
}

/// QR code generator using SVG format
pub struct QrGenerator;

impl QrGenerator {
    /// Generate QR code as SVG with responsive viewBox
    ///
    /// Library auto-calculates QR version based on data length.
    /// Size parameter must be >= actual matrix dimension.
    /// CSS handles max-width: 400px on container.
    pub fn generate_svg(payload: &QrPayload) -> Result<String> {
        let json = payload.to_json()
            .map_err(|e| anyhow::anyhow!("Failed to serialize QR: {}", e))?;

        // Size 200 is safe for all QR versions (largest Version 40 is 177x177)
        // Library sets viewBox automatically based on actual matrix dimension
        qrcode_generator::to_svg_to_string(
            json.as_bytes(),
            QrCodeEcc::Low,
            200,
            None::<&str>,
        ).context("Failed to generate QR SVG")
    }
}

/// HTML template renderer with Catppuccin Mocha theme
pub struct HtmlTemplate;

impl HtmlTemplate {
    /// Render the full pairing page with QR and SSE
    pub fn render(qr_svg: &str, status: &ConnectionStatus) -> String {
        format!(
            r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Comacode Pairing</title>
    <style>
        :root {{
            --ctp-base: #1E1E2E;
            --ctp-surface: #313244;
            --ctp-primary: #CBA6F7;
            --ctp-text: #CDD6F4;
            --ctp-green: #A6E3A1;
            --ctp-red: #F38BA8;
            --ctp-yellow: #F9E2AF;
            --ctp-overlay: #45475A;
        }}
        body {{
            background-color: var(--ctp-base);
            color: var(--ctp-text);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
        }}
        .container {{
            background-color: var(--ctp-surface);
            padding: 2rem;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
            text-align: center;
            max-width: 500px;
            width: 90%;
        }}
        h1 {{
            color: var(--ctp-primary);
            margin-bottom: 0.5rem;
            font-size: 1.8rem;
        }}
        .subtitle {{
            color: var(--ctp-text);
            opacity: 0.7;
            margin-bottom: 2rem;
            font-size: 0.9rem;
        }}
        .qr-container {{
            background-color: white;
            padding: 1rem;
            border-radius: 8px;
            display: block;
            margin: 0 auto 1.5rem;
            width: 100%;
            max-width: 400px;
        }}
        .qr-container svg {{
            display: block;
            margin: 0 auto;
        }}
        .status {{
            font-size: 1.1rem;
            margin-bottom: 1rem;
            padding: 0.75rem;
            border-radius: 8px;
            background-color: var(--ctp-overlay);
            transition: all 0.3s ease;
        }}
        .status.connected {{ color: var(--ctp-green); }}
        .status.waiting {{ color: var(--ctp-yellow); }}
        .status.disconnected {{ color: var(--ctp-red); }}
        .status.error {{ color: var(--ctp-red); }}
        .status.reconnect {{
            animation: pulse 1.5s infinite;
        }}
        @keyframes pulse {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.5; }}
        }}
        .info {{
            font-size: 0.8rem;
            color: var(--ctp-text);
            opacity: 0.6;
            margin-top: 2rem;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Comacode Pairing</h1>
        <p class="subtitle">Scan with mobile app to connect</p>
        <div class="qr-container">{}</div>
        <div id="status" class="status {}">{}</div>
        <p class="info">Keep this window open while connected</p>
    </div>
    <script>
        const RECONNECT_DELAY = 1000; // Constant 1s for localhost
        let reconnectAttempts = 0;
        let evtSource = null;
        let reconnectTimeout = null;

        function connectSSE() {{
            // Clear any pending reconnect
            if (reconnectTimeout) {{
                clearTimeout(reconnectTimeout);
                reconnectTimeout = null;
            }}

            evtSource = new EventSource('/api/status');

            evtSource.onopen = () => {{
                reconnectAttempts = 0;
                const statusEl = document.getElementById('status');
                statusEl.classList.remove('error', 'reconnect');
            }};

            evtSource.onmessage = (event) => {{
                const status = JSON.parse(event.data);
                const statusEl = document.getElementById('status');
                statusEl.textContent = status.message;
                statusEl.className = 'status ' + status.status;
            }};

            evtSource.onerror = () => {{
                evtSource.close();
                reconnectAttempts++;
                const statusEl = document.getElementById('status');

                if (reconnectAttempts > 3) {{
                    statusEl.textContent = 'Connection lost. Reconnecting...';
                    statusEl.classList.add('error', 'reconnect');
                }}

                // Constant 1s backoff - immediate for localhost UX
                reconnectTimeout = setTimeout(connectSSE, RECONNECT_DELAY);
            }};
        }}

        connectSSE();
    </script>
</body>
</html>"#,
            qr_svg,
            status.class(),
            status.message()
        )
    }
}

/// Main pairing page route handler
pub async fn pairing_page(State(state): State<WebState>) -> Result<Html<String>, String> {
    let payload = state.qr_payload.lock().await;
    let status = state.status.lock().await;

    match payload.as_ref() {
        Some(p) => {
            let qr_svg = QrGenerator::generate_svg(p)
                .map_err(|e| format!("QR generation failed: {}", e))?;
            let html = HtmlTemplate::render(&qr_svg, &status);
            Ok(Html(html))
        }
        None => Err("<html><body><h1>Not ready - please wait...</h1></body></html>".to_string()),
    }
}

/// SSE status stream handler
pub async fn status_stream(State(state): State<WebState>) -> Sse<impl Stream<Item = Result<Event, String>>> {
    let stream = async_stream::stream! {
        loop {{
            let status = state.status.lock().await.clone();
            let event = Event::default()
                .json_data(&status)
                .unwrap();
            yield Ok(event);
            tokio::time::sleep(Duration::from_secs(1)).await;
        }}
    };

    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(Duration::from_secs(30))
            .text("keepalive"),
    )
}

/// Web server for the pairing dashboard
pub struct WebServer {
    state: WebState,
}

impl WebServer {
    pub fn new() -> Self {
        Self {
            state: WebState::new(),
        }
    }

    /// Get the web state for external updates
    pub fn state(&self) -> WebState {
        self.state.clone()
    }

    /// Start the web server on loopback only
    ///
    /// # SECURITY
    /// - Only binds to 127.0.0.1 (loopback)
    /// - Auto-increments port if 3721 is taken
    /// - Returns the actual bound address
    pub async fn start(&self) -> Result<SocketAddr> {
        // SECURITY: Verify bind address is loopback
        let bind_addr: SocketAddr = WEB_BIND_ADDR.parse()
            .context("Invalid web bind address")?;

        assert!(bind_addr.ip().is_loopback(),
            "SECURITY: Web UI MUST bind to loopback only!");

        // Try ports 3721-3730 for fallback
        for port_offset in 0..10 {
            let port = 3721 + port_offset;
            let addr = SocketAddr::new(bind_addr.ip(), port);

            // Create Axum app
            let app = axum::Router::new()
                .route("/", axum::routing::get(pairing_page))
                .route("/api/status", axum::routing::get(status_stream))
                .with_state(self.state.clone());

            // Try to bind
            match tokio::net::TcpListener::bind(addr).await {
                Ok(listener) => {
                    info!("Web server listening on http://{}", addr);

                    // Spawn server task
                    tokio::spawn(async move {
                        axum::serve(
                            listener,
                            app.into_make_service(),
                        ).await.unwrap();
                    });

                    return Ok(addr);
                }
                Err(_e) => {
                    if port_offset == 0 {
                        warn!("Port {} in use, trying next port...", port);
                    }
                    continue;
                }
            }
        }

        Err(anyhow::anyhow!("No available ports for web server (tried 3721-3730)"))
    }

    /// Open browser to the web dashboard
    pub fn open_browser(url: &str) -> Result<()> {
        open::that(url)
            .context("Failed to open browser")
    }
}

impl Default for WebServer {
    fn default() -> Self {
        Self::new()
    }
}
