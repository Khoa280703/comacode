//! QR code payload for terminal pairing
//!
//! # Phase E04 - Certificate Persistence + TOFU
//!
//! QrPayload contains connection information encoded as QR code
//! for mobile clients to scan and establish initial trust.

use crate::error::{CoreError, Result};
use crate::PROTOCOL_VERSION;
use serde::{Deserialize, Serialize};

/// QR code payload for pairing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrPayload {
    /// Host IP address
    pub ip: String,

    /// Host port
    pub port: u16,

    /// Certificate fingerprint (SHA-256, hex format with colons)
    pub fingerprint: String,

    /// Auth token (hex format)
    pub token: String,

    /// Protocol version
    pub protocol_version: u32,
}

impl QrPayload {
    /// Create new QR payload
    pub fn new(ip: String, port: u16, fingerprint: String, token: String) -> Self {
        Self {
            ip,
            port,
            fingerprint,
            token,
            protocol_version: PROTOCOL_VERSION,
        }
    }

    /// Serialize to JSON string (for QR encoding)
    pub fn to_json(&self) -> Result<String> {
        serde_json::to_string(self)
            .map_err(|e| CoreError::Protocol(format!("JSON serialization failed: {}", e)))
    }

    /// Deserialize from JSON string
    pub fn from_json(json: &str) -> Result<Self> {
        serde_json::from_str(json)
            .map_err(|e| CoreError::Protocol(format!("JSON deserialization failed: {}", e)))
    }

    /// Render QR code as Unicode string (for terminal display)
    ///
    /// **IMPORTANT**: Uses Dense1x2 Unicode renderer for terminal.
    /// NOT SVG - SVG will print as garbage XML text.
    ///
    /// # Example
    /// ```
    /// # use comacode_core::QrPayload;
    /// let payload = QrPayload::new(
    ///     "192.168.1.1".to_string(),
    ///     8443,
    ///     "AA:BB:CC".to_string(),
    ///     "deadbeef".to_string(),
    /// );
    /// let qr = payload.to_qr_terminal().unwrap();
    /// println!("{}", qr);
    /// ```
    pub fn to_qr_terminal(&self) -> Result<String> {
        use qrcode::render::unicode;

        let json = self.to_json()?;

        // Generate QR code
        let qr_code = qrcode::QrCode::new(json)
            .map_err(|e| CoreError::QrGenerationError(e.to_string()))?;

        // Render to Unicode (Dense1x2 = high density, scan-able)
        // Note: Dark on terminal = Light char, Light background = Dark char
        let image = qr_code
            .render::<unicode::Dense1x2>()
            .dark_color(unicode::Dense1x2::Light)
            .light_color(unicode::Dense1x2::Dark)
            .build();

        Ok(image)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_qr_payload_creation() {
        let payload = QrPayload::new(
            "192.168.1.1".to_string(),
            8443,
            "AA:BB:CC:DD".to_string(),
            "deadbeef".to_string(),
        );
        assert_eq!(payload.ip, "192.168.1.1");
        assert_eq!(payload.port, 8443);
        assert_eq!(payload.fingerprint, "AA:BB:CC:DD");
        assert_eq!(payload.token, "deadbeef");
        assert_eq!(payload.protocol_version, PROTOCOL_VERSION);
    }

    #[test]
    fn test_qr_payload_json_roundtrip() {
        let original = QrPayload::new(
            "192.168.1.1".to_string(),
            8443,
            "AA:BB:CC:DD".to_string(),
            "deadbeef".to_string(),
        );

        let json = original.to_json().unwrap();
        let decoded = QrPayload::from_json(&json).unwrap();

        assert_eq!(decoded.ip, original.ip);
        assert_eq!(decoded.port, original.port);
        assert_eq!(decoded.fingerprint, original.fingerprint);
        assert_eq!(decoded.token, original.token);
        assert_eq!(decoded.protocol_version, original.protocol_version);
    }

    #[test]
    fn test_qr_payload_to_qr_terminal() {
        let payload = QrPayload::new(
            "127.0.0.1".to_string(),
            8443,
            "AA:BB:CC".to_string(),
            "test".to_string(),
        );

        let qr = payload.to_qr_terminal();
        assert!(qr.is_ok());

        let qr_string = qr.unwrap();
        // Unicode QR should contain visible characters
        assert!(!qr_string.is_empty());
        assert!(qr_string.len() > 100);
    }

    #[test]
    fn test_qr_payload_serialize() {
        let payload = QrPayload::new(
            "10.0.0.1".to_string(),
            9000,
            "FF:EE:DD".to_string(),
            "cafe".to_string(),
        );

        let json = payload.to_json().unwrap();
        // JSON should contain all fields
        assert!(json.contains("\"ip\":"));
        assert!(json.contains("\"port\":"));
        assert!(json.contains("\"fingerprint\":"));
        assert!(json.contains("\"token\":"));
        assert!(json.contains("\"protocol_version\":"));
    }

    #[test]
    fn test_qr_payload_deserialize_invalid() {
        let result = QrPayload::from_json("invalid json");
        assert!(result.is_err());
    }

    #[test]
    fn test_qr_payload_empty_json() {
        let result = QrPayload::from_json("{}");
        // Missing required fields should fail
        assert!(result.is_err());
    }
}
