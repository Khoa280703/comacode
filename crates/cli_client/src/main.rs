//! Minimal QUIC client để test Comacode backend
//!
//! Features:
//! - Connect to hostagent via QUIC
//! - Send/receive NetworkMessage
//! - Interactive command mode
//! - Test auth + rate limiting + TOFU

use anyhow::Result;
use clap::Parser;
use comacode_core::{AuthToken, MessageCodec, NetworkMessage};
use quinn::{Endpoint, ClientConfig};
use rustls::ClientConfig as RustlsClientConfig;
use rustls::client::danger::{ServerCertVerifier, ServerCertVerified, HandshakeSignatureValid};
use rustls::crypto::ring::default_provider;
use rustls::DigitallySignedStruct;
use rustls::SignatureScheme;
use std::net::SocketAddr;
use std::sync::Arc;

#[derive(Parser, Debug)]
struct Args {
    /// Host address to connect to
    #[arg(short, long, default_value = "127.0.0.1:8443")]
    connect: SocketAddr,

    /// Auth token (REQUIRED - copy from hostagent output)
    #[arg(short, long)]
    token: String,

    /// Skip certificate verification (TESTING ONLY)
    #[arg(long, default_value_t = false)]
    insecure: bool,
}

/// Certificate verifier that skips verification (TESTING ONLY)
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
    // Install default crypto provider cho rustls 0.23
    default_provider().install_default().expect("Failed to install crypto provider");

    let args = Args::parse();

    println!("🔧 Comacode CLI Client");
    println!("📡 Connecting to {}...", args.connect);

    // Validate token format (must be 64 hex chars)
    let token = AuthToken::from_hex(&args.token)
        .map_err(|_| anyhow::anyhow!("Invalid token format. Expected 64 hex characters from hostagent."))?;

    // Create QUIC endpoint
    let mut endpoint = Endpoint::client("0.0.0.0:0".parse()?)?;

    // Configure TLS (skip verification for testing)
    if !args.insecure {
        return Err(anyhow::anyhow!("Proper verification not implemented, use --insecure for testing"));
    }

    // Build rustls client config with custom certificate verifier
    let crypto = RustlsClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SkipVerification))
        .with_no_client_auth();

    // Convert to quinn-compatible config
    let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(crypto)
        .map_err(|e| anyhow::anyhow!("Failed to create QUIC config: {}", e))?;

    let config = ClientConfig::new(Arc::new(quic_crypto));
    endpoint.set_default_client_config(config);

    // Connect to host
    let connecting = endpoint.connect(args.connect, "comacode.local")?;
    let connection = connecting.await?;

    println!("✅ Connected to {}", args.connect);

    // Open bidirectional stream
    let (mut send, mut recv) = connection.open_bi().await?;
    println!("📡 Stream opened");

    // Send Hello with validated token (already validated above)
    let hello = NetworkMessage::hello(Some(token));
    let encoded = MessageCodec::encode(&hello)?;
    send.write_all(&encoded).await?;
    println!("🤝 Handshake sent");

    // Read Hello response
    let mut buf = vec![0u8; 4096];
    let n = match recv.read(&mut buf).await? {
        Some(n) => n,
        None => return Err(anyhow::anyhow!("Connection closed during handshake")),
    };
    let response = MessageCodec::decode(&buf[..n])?;
    println!("✅ Handshake complete: {:?}", std::mem::discriminant(&response));

    // Test: Send Ping and wait for Pong
    let ping = NetworkMessage::ping();
    send.write_all(&MessageCodec::encode(&ping)?).await?;
    println!("📝 Ping sent");

    // Read response with timeout
    let start = std::time::Instant::now();
    let timeout_duration = std::time::Duration::from_secs(5);
    let mut received_pong = false;

    while start.elapsed() < timeout_duration {
        match recv.read(&mut buf).await? {
            Some(n) if n > 0 => {
                match MessageCodec::decode(&buf[..n]) {
                    Ok(msg) => match msg {
                        NetworkMessage::Pong { timestamp } => {
                            println!("✅ Received Pong (timestamp: {})", timestamp);
                            received_pong = true;
                            break;
                        }
                        _ => {
                            println!("📨 Received: {:?}", std::mem::discriminant(&msg));
                        }
                    },
                    Err(_) => {
                        // Not a valid message
                        println!("📨 Raw data: {} bytes", n);
                    }
                }
            }
            Some(_) | None => {
                if received_pong {
                    break;
                }
                // Continue waiting
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            }
        }
    }

    if received_pong {
        println!("✅ Ping/Pong test successful!");
    } else {
        println!("⚠️  No Pong received (timeout)");
    }

    // Send Close to gracefully end connection
    let close = NetworkMessage::Close;
    send.write_all(&MessageCodec::encode(&close)?).await?;
    println!("📡 Closing connection");

    Ok(())
}
