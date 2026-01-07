//! Error types for comacode-core

use thiserror::Error;

/// Core error type
#[derive(Debug, Error)]
pub enum CoreError {
    #[error("Serialization failed: {0}")]
    Serialization(#[from] postcard::Error),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Invalid message format: {0}")]
    InvalidMessageFormat(String),

    #[error("Message too large: {size} bytes (max: {max})")]
    MessageTooLarge { size: usize, max: usize },

    #[error("Terminal error: {0}")]
    Terminal(String),

    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Timeout after {0}ms")]
    Timeout(u64),

    #[error("Not connected")]
    NotConnected,

    #[error("Already connected")]
    AlreadyConnected,

    #[error("Invalid state: {0}")]
    InvalidState(String),

    #[error("Protocol version mismatch: expected {expected}, got {got}")]
    ProtocolVersionMismatch { expected: u32, got: u32 },

    #[error("Invalid handshake message")]
    InvalidHandshake,

    // Phase E03: Authentication errors
    #[error("Authentication failed: invalid token")]
    AuthFailed,

    #[error("Missing authentication token")]
    MissingAuthToken,

    #[error("Invalid token format")]
    InvalidTokenFormat,

    #[error("IP address {ip} is banned")]
    IpBanned { ip: std::net::IpAddr },

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    // Phase E04: Certificate & QR errors
    #[error("Certificate parse error: {0}")]
    CertParseError(String),

    #[error("No data directory found")]
    NoDataDir,

    #[error("QR code generation error: {0}")]
    QrGenerationError(String),

    #[error("Fingerprint mismatch for host {host}: expected {expected}, got {got}")]
    FingerprintMismatch {
        host: String,
        expected: String,
        got: String,
    },

    #[error("Network error: {0}")]
    NetworkError(String),
}

/// Result type alias
pub type Result<T> = std::result::Result<T, CoreError>;

impl From<quinn::ConnectionError> for CoreError {
    fn from(err: quinn::ConnectionError) -> Self {
        CoreError::Connection(err.to_string())
    }
}

impl From<quinn::WriteError> for CoreError {
    fn from(err: quinn::WriteError) -> Self {
        CoreError::Io(std::io::Error::new(std::io::ErrorKind::BrokenPipe, err))
    }
}

impl From<quinn::ReadError> for CoreError {
    fn from(err: quinn::ReadError) -> Self {
        CoreError::Io(std::io::Error::new(std::io::ErrorKind::BrokenPipe, err))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = CoreError::NotConnected;
        assert_eq!(err.to_string(), "Not connected");
    }

    #[test]
    fn test_error_conversion() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "test");
        let core_err: CoreError = io_err.into();
        assert!(matches!(core_err, CoreError::Io(_)));
    }

    #[test]
    fn test_protocol_version_mismatch_error() {
        let err = CoreError::ProtocolVersionMismatch { expected: 1, got: 2 };
        assert_eq!(err.to_string(), "Protocol version mismatch: expected 1, got 2");
    }

    #[test]
    fn test_invalid_handshake_error() {
        let err = CoreError::InvalidHandshake;
        assert_eq!(err.to_string(), "Invalid handshake message");
    }
}
