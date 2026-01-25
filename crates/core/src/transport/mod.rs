//! QUIC transport configuration helpers
//!
//! This module provides QUIC client/server configuration with proper settings:
//! - Appropriate timeouts for mobile scenarios
//! - Keep-alive for NAT traversal
//! - Flow control settings

pub mod stream;

pub use stream::{BufferConfig, pump_pty_to_quic, pump_pty_to_quic_smart, pump_pty_to_quic_tagged};

use quinn::{ClientConfig, ServerConfig, TransportConfig};
use std::sync::Arc;
use std::time::Duration;

use crate::{CoreError, Result};

/// Configure QUIC client with proper settings for mobile use
///
/// # Features
/// - 30s idle timeout (elevator/tunnel scenarios)
/// - 5s keep-alive interval (NAT traversal)
pub fn configure_client(crypto_config: Arc<quinn::crypto::rustls::QuicClientConfig>) -> ClientConfig {
    let mut transport = TransportConfig::default();

    // Timeout 30s for elevator/tunnel scenarios
    // Mobile devices frequently lose signal briefly
    transport.max_idle_timeout(
        Some(Duration::from_secs(30).try_into().unwrap())
    );

    // Keep-alive interval (5s) to prevent NAT timeout
    // Most NAT devices timeout connections after 30-60s of inactivity
    transport.keep_alive_interval(Some(Duration::from_secs(5)));

    let mut config = ClientConfig::new(crypto_config);
    config.transport_config(Arc::new(transport));
    config
}

/// Configure QUIC server with proper settings
///
/// # Features
/// - 30s idle timeout (matches client)
/// - 5s keep-alive interval (matches client)
pub fn configure_server(cert: Vec<rustls::pki_types::CertificateDer<'static>>, key: rustls::pki_types::PrivateKeyDer<'static>) -> Result<ServerConfig> {
    let mut transport = TransportConfig::default();

    // Match client timeout settings
    transport.max_idle_timeout(
        Some(Duration::from_secs(30).try_into().unwrap())
    );

    // Keep-alive to detect dead clients
    transport.keep_alive_interval(Some(Duration::from_secs(5)));

    let mut config = ServerConfig::with_single_cert(cert, key)
        .map_err(|e| CoreError::Protocol(format!("Failed to configure TLS: {}", e)))?;

    config.transport_config(Arc::new(transport));
    Ok(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_configure_client_creates_valid_config() {
        // Note: Cannot easily test without actual crypto config
        // The function itself is tested via integration tests
    }

    #[test]
    fn test_configure_server_creates_valid_config() {
        // Generate a self-signed cert for testing
        let cert = rcgen::generate_simple_self_signed(["localhost".to_string()]).unwrap();
        let cert_der = rustls::pki_types::CertificateDer::from(cert.cert);
        let key_der = rustls::pki_types::PrivateKeyDer::Pkcs8(
            rustls::pki_types::PrivatePkcs8KeyDer::from(cert.key_pair.serialize_der())
        );

        let config = configure_server(vec![cert_der], key_der);
        assert!(config.is_ok());
    }
}
