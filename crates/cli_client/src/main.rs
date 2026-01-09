//! QUIC client for Comacode remote terminal
//! Features: SSH-like raw mode, eager spawn, proper resize

mod message_reader;
mod raw_mode;

use anyhow::Result;
use clap::Parser;
use comacode_core::{AuthToken, MessageCodec, NetworkMessage, TerminalEvent};
use message_reader::MessageReader;
use crossterm::terminal::size;
use quinn::{ClientConfig, Endpoint};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::ring::default_provider;
use rustls::ClientConfig as RustlsClientConfig;
use rustls::DigitallySignedStruct;
use rustls::SignatureScheme;
use std::io::{Read, Write};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::signal::unix::{signal, SignalKind};
use tokio::sync::mpsc;

// CLI argument parser and TLS verification
#[derive(Parser, Debug)]
struct Args {
    #[arg(short, long, default_value = "127.0.0.1:8443")]
    connect: SocketAddr,
    #[arg(short, long)]
    token: String,
    #[arg(long, default_value_t = false)]
    insecure: bool,
}

#[derive(Debug)]
struct SkipVerification;
impl ServerCertVerifier for SkipVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }
    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![
            SignatureScheme::RSA_PKCS1_SHA1,
            SignatureScheme::ECDSA_SHA1_Legacy,
            SignatureScheme::RSA_PKCS1_SHA256,
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::RSA_PKCS1_SHA384,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::RSA_PKCS1_SHA512,
            SignatureScheme::ECDSA_NISTP521_SHA512,
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::ED25519,
            SignatureScheme::ED448,
        ]
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    default_provider()
        .install_default()
        .expect("Failed to install crypto provider");
    let args = Args::parse();

    println!("Comacode CLI Client v{}", env!("CARGO_PKG_VERSION"));
    println!("Connecting to {}...", args.connect);
    let token = AuthToken::from_hex(&args.token).map_err(|_| anyhow::anyhow!("Invalid token"))?;
    let mut endpoint = Endpoint::client("0.0.0.0:0".parse()?)?;
    if !args.insecure {
        return Err(anyhow::anyhow!("Use --insecure"));
    }
    let crypto = RustlsClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SkipVerification))
        .with_no_client_auth();
    let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(crypto).unwrap();
    endpoint.set_default_client_config(ClientConfig::new(Arc::new(quic_crypto)));

    let connecting = endpoint.connect(args.connect, "comacode.local")?;
    let connection = connecting.await?;
    let (mut send, recv) = connection.open_bi().await?;

    // Handshake: Send Hello, read response with proper framing
    let hello = NetworkMessage::hello(Some(token));
    send.write_all(&MessageCodec::encode(&hello)?).await?;
    let mut reader = MessageReader::new(recv);
    let _ = reader.read_message().await?;
    println!("Authenticated");

    // ===== 1. BANNER & RAW MODE =====
    let _ = std::io::stdout().write_all(b"\x1b]0;[COMACODE] Remote Session\x07");

    // Get current time for banner
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let datetime = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap_or_default()
        .format("%Y-%m-%d %H:%M:%S UTC");

    let banner = format!(
        "\r\n\
        \x1b[1;36m╔═══════════════════════════════════════════════════════╗\x1b[0m\r\n\
        \x1b[1;36m║\x1b[1;33m         ⚡ COMACODE REMOTE TERMINAL ⚡\x1b[1;36m              ║\x1b[0m\r\n\
        \x1b[1;36m╠═══════════════════════════════════════════════════════╣\x1b[0m\r\n\
        \x1b[1;36m║\x1b[0m \x1b[90mHost:\x1b[0m     {:<48} \x1b[1;36m║\x1b[0m\r\n\
        \x1b[1;36m║\x1b[0m \x1b[90mConnected:\x1b[0m {:<44} \x1b[1;36m║\x1b[0m\r\n\
        \x1b[1;36m║\x1b[0m \x1b[90mExit cmd:\x1b[0m  \x1b[33m/exit\x1b[0m \x1b[90m(disconnects gracefully)\x1b[0m      \x1b[1;36m║\x1b[0m\r\n\
        \x1b[1;36m╚═══════════════════════════════════════════════════════╝\x1b[0m\r\n\r\n",
        args.connect, datetime
    );
    let _ = std::io::stdout().write_all(banner.as_bytes());
    let _ = std::io::stdout().flush();

    // Enable raw mode for terminal input
    // Fallback: continue without raw mode in non-TTY environments
    let _guard = match raw_mode::RawModeGuard::enable() {
        Ok(guard) => Some(guard),
        Err(e) => {
            eprintln!("Warning: Raw mode not available: {}. Input may be slow.", e);
            None
        }
    };

    // ===== 2. EAGER SPAWN SEQUENCE (SSH-LIKE) =====
    // Send Resize -> Empty Input to spawn session
    if let Ok((cols, rows)) = size() {
        let resize = NetworkMessage::Resize { rows, cols };
        send.write_all(&MessageCodec::encode(&resize)?).await?;
    }

    // Trigger Spawn: Send empty Input to spawn session on server
    let spawn_trigger = NetworkMessage::Input { data: vec![] };
    send.write_all(&MessageCodec::encode(&spawn_trigger)?)
        .await?;

    // ===== 3. INTERACTIVE LOOP =====
    // Spawn stdin task immediately - no need to wait for prompt
    // User input is buffered and sent (type-ahead)

    let (stdin_tx, mut stdin_rx) = mpsc::channel::<Vec<u8>>(32);

    // Track if raw mode is enabled for stdin_task
    let raw_mode_enabled = _guard.is_some();

    // SIGWINCH handler for dynamic terminal resize
    let resize_tx = stdin_tx.clone();
    tokio::spawn(async move {
        match signal(SignalKind::window_change()) {
            Ok(mut stream) => {
                loop {
                    stream.recv().await;
                    if let Ok((cols, rows)) = size() {
                        let resize_msg = NetworkMessage::Resize { rows, cols };
                        if let Ok(encoded) = MessageCodec::encode(&resize_msg) {
                            let _ = resize_tx.send(encoded).await;
                        }
                    }
                }
            }
            Err(_) => {
                // SIGWINCH not available on this platform (e.g., Windows)
            }
        }
    });

    // stdin_task: different behavior based on raw mode availability
    let mut stdin_task = if raw_mode_enabled {
        // === RAW MODE: byte-by-byte for interactive shell ===
        // Accumulate lines to detect /exit command
        tokio::task::spawn_blocking(move || {
            let mut stdin = std::io::stdin();
            let mut buf = [0u8; 1024];
            let mut line_buf = Vec::new(); // Accumulate line for /exit detection

            loop {
                match stdin.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        let data = &buf[..n];

                        // Check for /exit in accumulated line
                        line_buf.extend_from_slice(data);
                        if line_buf.contains(&b'/') && line_buf.windows(5).any(|w| w == b"/exit") {
                            std::thread::sleep(std::time::Duration::from_secs(2));
                            break;
                        }
                        // Clear line buffer on newline
                        if data.contains(&b'\n') {
                            line_buf.clear();
                        }

                        // Send raw bytes
                        let msg = NetworkMessage::Input {
                            data: data.to_vec(),
                        };
                        if let Ok(encoded) = MessageCodec::encode(&msg) {
                            if stdin_tx.blocking_send(encoded).is_err() {
                                break;
                            }
                        }
                    }
                    Err(_) => break,
                }
            }
        })
    } else {
        // === LINE-BUFFERED: for piped input / non-TTY ===
        tokio::task::spawn_blocking(move || {
            use std::io::BufRead;

            let stdin = std::io::stdin();
            let reader = stdin.lock();
            let mut lines = reader.lines();

            loop {
                match lines.next() {
                    None => break,
                    Some(Ok(line)) => {
                        if line.trim() == "/exit" {
                            std::thread::sleep(std::time::Duration::from_secs(2));
                            break;
                        }
                        let full_line = format!("{}\n", line);
                        let msg = NetworkMessage::Input {
                            data: full_line.into_bytes(),
                        };
                        if let Ok(encoded) = MessageCodec::encode(&msg) {
                            if stdin_tx.blocking_send(encoded).is_err() {
                                break;
                            }
                        }
                    }
                    Some(Err(_)) => break,
                }
            }
        })
    };

    let mut stdin_eof = false;

    loop {
        tokio::select! {
            _ = &mut stdin_task => { stdin_eof = true; }
            Some(encoded) = stdin_rx.recv() => {
                if send.write_all(&encoded).await.is_err() { break; }
            }
            // Use MessageReader for proper framing
            result = reader.read_message() => {
                match result {
                    Ok(msg) => {
                        match msg {
                            NetworkMessage::Event(TerminalEvent::Output { data }) => {
                                let mut stdout = std::io::stdout();
                                let _ = stdout.write_all(&data);
                                let _ = stdout.flush();
                            }
                            NetworkMessage::Close => break,
                            _ => {}
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        if stdin_eof && stdin_rx.is_empty() {
            // Give server time to send final responses (command output, etc.)
            // Commands can take time to execute
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            if stdin_rx.is_empty() {
                break;
            }
        }
    }

    stdin_task.abort();

    // Reset Terminal
    let _ = std::io::stdout().write_all(b"\x1b]0;\x07\x1b[!p\x1bc\r\nConnection closed.\r\n");
    let _ = std::io::stdout().flush();
    let _ = send
        .write_all(&MessageCodec::encode(&NetworkMessage::Close)?)
        .await;

    Ok(())
}
