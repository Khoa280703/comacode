//! QUIC client for Flutter bridge
//!
//! Phase 04: Mobile App - QUIC client with TOFU verification
//!
//! ## Implementation Notes
//!
//! Uses Quinn 0.11 + Rustls 0.23 with custom TOFU (Trust On First Use) certificate verifier.
//! The fingerprint is normalized (case-insensitive, separator-agnostic) before comparison.

use comacode_core::{TerminalEvent, AuthToken};
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, error, debug};

// Quinn imports
use quinn::{ClientConfig, Endpoint, Connection};

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

        debug!("Verifying cert - Expected: {}, Actual: {}", self.expected_fingerprint, actual_clean);

        if actual_clean == expected_clean {
            Ok(ServerCertVerified::assertion())
        } else {
            error!(
                "Fingerprint mismatch! Expected: {}, Got: {}",
                self.expected_fingerprint, actual_clean
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
        let _token = AuthToken::from_hex(&auth_token)
            .map_err(|e| format!("Invalid auth token: {}", e))?;

        info!("Connecting to {}:{} with TOFU fingerprint verification...", host, port);

        // Step 1: Setup Rustls config with TOFU verifier
        let verifier = Arc::new(TofuVerifier::new(self.server_fingerprint.clone()));

        let rustls_config = rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth();

        // Step 2: Wrap into Quinn config
        let quic_crypto = quinn::crypto::rustls::QuicClientConfig::try_from(rustls_config)
            .map_err(|e| format!("Failed to create QUIC crypto config: {}", e))?;

        let mut client_config = ClientConfig::new(Arc::new(quic_crypto));

        // Step 3: Configure transport (timeout, keep-alive)
        let mut transport_config = quinn::TransportConfig::default();
        transport_config.max_idle_timeout(Some(Duration::from_secs(10).try_into().unwrap()));
        client_config.transport_config(Arc::new(transport_config));

        // Step 4: Connect to server
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

        // TODO: Handshake protocol (send auth token) in later phase
        self.connection = Some(connection);
        Ok(())
    }

    /// Receive next terminal event from server
    ///
    /// TODO: Implement actual QUIC stream reading
    pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
        if self.connection.is_none() {
            return Err("Not connected".to_string());
        }

        // TODO: Actually receive from QUIC stream
        // For now, return empty output
        Ok(TerminalEvent::output_str(""))
    }

    /// Send command to remote terminal
    ///
    /// TODO: Implement actual QUIC stream writing
    pub async fn send_command(&self, command: String) -> Result<(), String> {
        if self.connection.is_none() {
            return Err("Not connected".to_string());
        }

        // TODO: Actually send via QUIC stream
        info!("QUIC client: would send command: {}", command);
        Ok(())
    }

    /// Disconnect from server
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if let Some(conn) = &self.connection {
            conn.close(0u32.into(), b"Client disconnect");
        }
        self.connection = None;
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
