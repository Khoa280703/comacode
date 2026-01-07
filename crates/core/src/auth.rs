//! Authentication token types for secure session access
//!
//! # Phase E03 - Security Hardening
//!
//! AuthToken provides 256-bit random token generation with hex encoding/decoding.
//!
//! ## Security Notes
//!
//! - **Copy trait**: Token is only 32 bytes, cheap to copy
//! - **Hash trait**: Enables HashSet storage for O(1) lookup
//! - **Random generation**: Uses thread_rng() from rand crate
//! - **Timing attack**: HashSet::contains() accepted for MVP (see validate() docs)

use crate::error::CoreError;
use rand::Rng;
use serde::{Deserialize, Serialize};

/// Token size in bytes (256-bit)
const TOKEN_SIZE: usize = 32;

/// Authentication token for session access
///
/// 256-bit random token used for authenticating mobile clients.
///
/// ## Derives
/// - `Copy`: 32 bytes is cheap to copy by value
/// - `Hash`: Enables HashSet storage for O(1) lookup
/// - `Eq`: Required for Hash, enables exact comparison
/// - `Serialize/Deserialize`: For Postcard protocol encoding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AuthToken([u8; TOKEN_SIZE]);

impl AuthToken {
    /// Generate a new random authentication token
    ///
    /// Uses cryptographically secure random number generation
    /// from rand::thread_rng().
    ///
    /// # Example
    /// ```
    /// # use comacode_core::auth::AuthToken;
    /// let token = AuthToken::generate();
    /// assert_eq!(token.as_bytes().len(), 32);
    /// ```
    pub fn generate() -> Self {
        let mut bytes = [0u8; TOKEN_SIZE];
        rand::thread_rng().fill(&mut bytes);
        Self(bytes)
    }

    /// Create token from hexadecimal string
    ///
    /// # Errors
    /// - `InvalidTokenFormat` if hex string is not exactly 64 characters
    /// - `InvalidTokenFormat` if hex string contains non-hex characters
    ///
    /// # Example
    /// ```
    /// # use comacode_core::auth::AuthToken;
    /// let token = AuthToken::generate();
    /// let hex = token.to_hex();
    /// let decoded = AuthToken::from_hex(&hex).unwrap();
    /// assert_eq!(token, decoded);
    /// ```
    pub fn from_hex(hex: &str) -> Result<Self, CoreError> {
        if hex.len() != TOKEN_SIZE * 2 {
            return Err(CoreError::InvalidTokenFormat);
        }

        let mut bytes = [0u8; TOKEN_SIZE];
        for i in 0..TOKEN_SIZE {
            bytes[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16)
                .map_err(|_| CoreError::InvalidTokenFormat)?;
        }
        Ok(Self(bytes))
    }

    /// Export token as hexadecimal string
    ///
    /// Returns a 64-character hex string (lowercase).
    ///
    /// # Example
    /// ```
    /// # use comacode_core::auth::AuthToken;
    /// let token = AuthToken::generate();
    /// let hex = token.to_hex();
    /// assert_eq!(hex.len(), 64);
    /// ```
    pub fn to_hex(&self) -> String {
        self.0.iter().map(|b| format!("{:02x}", b)).collect()
    }

    /// Get raw bytes reference
    ///
    /// Returns reference to the 32-byte array.
    pub fn as_bytes(&self) -> &[u8; TOKEN_SIZE] {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_generation() {
        let token1 = AuthToken::generate();
        let token2 = AuthToken::generate();
        assert_ne!(token1, token2, "Tokens should be unique");
    }

    #[test]
    fn test_token_size() {
        let token = AuthToken::generate();
        assert_eq!(token.as_bytes().len(), 32);
    }

    #[test]
    fn test_token_hex_length() {
        let token = AuthToken::generate();
        let hex = token.to_hex();
        assert_eq!(hex.len(), 64);
    }

    #[test]
    fn test_token_hex_roundtrip() {
        let token = AuthToken::generate();
        let hex = token.to_hex();
        let decoded = AuthToken::from_hex(&hex).unwrap();
        assert_eq!(token, decoded);
    }

    #[test]
    fn test_token_from_hex_invalid_length() {
        let result = AuthToken::from_hex("abc123");
        assert!(matches!(result, Err(CoreError::InvalidTokenFormat)));
    }

    #[test]
    fn test_token_from_hex_invalid_chars() {
        let result = AuthToken::from_hex("gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg");
        assert!(matches!(result, Err(CoreError::InvalidTokenFormat)));
    }

    #[test]
    fn test_token_copy() {
        let token1 = AuthToken::generate();
        let token2 = token1; // Copy, not move
        assert_eq!(token1, token2);
    }

    #[test]
    fn test_token_hash() {
        use std::collections::HashSet;
        let mut set = HashSet::new();
        let token = AuthToken::generate();
        set.insert(token);
        assert!(set.contains(&token));
    }
}
