//! QUIC client for Flutter bridge
//!
//! Phase 04: Mobile App - QUIC client with TOFU verification
//!
//! ## Implementation Notes
//!
//! Uses Quinn 0.11 + Rustls 0.23 with custom TOFU (Trust On First Use) certificate verifier.
//! The fingerprint is normalized (case-insensitive, separator-agnostic) before comparison.

use comacode_core::{TerminalEvent, AuthToken};
use comacode_core::protocol::MessageCodec;
use comacode_core::types::{NetworkMessage, TerminalCommand};
use quinn::{ClientConfig, Endpoint, Connection, RecvStream, SendStream};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tracing::{info, error, debug};

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
    /// QUIC receive stream for terminal events
    recv_stream: Option<Arc<Mutex<RecvStream>>>,
    /// Background task for receiving terminal events
    recv_task: Option<JoinHandle<()>>,
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
            recv_stream: None,
            recv_task: None,
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
        self.recv_stream = Some(recv_shared.clone());

        // Step 8: Spawn background receive task (Phase 05.1)
        // Note: For now, we don't implement background receiving
        // The receive_event() method will read directly from the stream
        self.connection = Some(connection);
        Ok(())
    }

    /// Receive next terminal event from server
    ///
    /// Phase 05.1: Reads from QUIC stream and returns terminal events
    pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
        let recv_stream = self.recv_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let mut recv = recv_stream.lock().await;
        let mut read_buf = vec![0u8; 8192];

        // Read from stream
        let n = recv.read(&mut read_buf).await
            .map_err(|e| format!("Failed to read from stream: {}", e))?
            .ok_or_else(|| format!("Connection closed"))?;

        if n == 0 {
            return Ok(TerminalEvent::output_str(""));
        }

        // Decode message
        let msg = MessageCodec::decode(&read_buf[..n])
            .map_err(|e| format!("Failed to decode message: {}", e))?;

        match msg {
            NetworkMessage::Event(event) => Ok(event),
            NetworkMessage::Input { .. } | NetworkMessage::Command(_) => {
                // Input/Command messages from server (unlikely in receive path)
                Ok(TerminalEvent::output_str(""))
            }
            NetworkMessage::Hello { .. } | NetworkMessage::Ping { .. } | NetworkMessage::Pong { .. } => {
                Ok(TerminalEvent::output_str(""))
            }
            NetworkMessage::Resize { .. } => Ok(TerminalEvent::output_str("")),
            NetworkMessage::RequestPty { .. } | NetworkMessage::StartShell => {
                Ok(TerminalEvent::output_str(""))
            }
            NetworkMessage::RequestSnapshot => Ok(TerminalEvent::output_str("")),
            NetworkMessage::Snapshot { .. } => Ok(TerminalEvent::output_str("")),
            NetworkMessage::Close => Ok(TerminalEvent::output_str("")),
        }
    }

    /// Send command to remote terminal
    ///
    /// Phase 05.1: Sends command via QUIC stream
    pub async fn send_command(&self, command: String) -> Result<(), String> {
        let send_stream = self.send_stream.as_ref()
            .ok_or_else(|| "Not connected".to_string())?;

        let cmd_msg = NetworkMessage::Command(TerminalCommand::new(command));
        let encoded = MessageCodec::encode(&cmd_msg)
            .map_err(|e| format!("Failed to encode command: {}", e))?;

        let mut send = send_stream.lock().await;
        send.write_all(&encoded).await
            .map_err(|e| format!("Failed to send command: {}", e))?;

        debug!("Sent command via QUIC");
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

    /// Disconnect from server
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if let Some(conn) = &self.connection {
            conn.close(0u32.into(), b"Client disconnect");
        }
        self.connection = None;
        self.send_stream = None;
        self.recv_stream = None;
        self.recv_task = None;
        Ok(())
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        match &self.connection {
            Some(conn) => conn.close_reason().is_none(),
            None => false,
        }
    }
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
