//! Token storage and validation for Phase E03 Security Hardening
//!
//! # TokenStore
//!
//! Manages valid authentication tokens using HashSet for O(1) lookup.
//!
//! ## Security Note: Timing Attack Consideration
//!
//! HashSet::contains() is NOT constant-time comparison.
//!
//! ### Why this is ACCEPTED for MVP:
//! - Token is 256-bit random (2^256 entropy) - brute force infeasible
//! - Attacker does NOT control token content (server-generated)
//! - HashSet hash first → timing variation smaller than direct string compare
//! - Token is like a random API key, not a user-chosen password
//!
//! ### Future Enhancement:
//! - Use constant_time_eq crate if compliance requires (FIPS, etc.)

use comacode_core::auth::AuthToken;
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Token storage for validating authentication
#[derive(Clone)]
pub struct TokenStore {
    valid_tokens: Arc<RwLock<HashSet<AuthToken>>>,
}

impl TokenStore {
    /// Create new empty token store
    pub fn new() -> Self {
        Self {
            valid_tokens: Arc::new(RwLock::new(HashSet::new())),
        }
    }

    /// Add valid token (e.g., from QR code scan)
    pub async fn add_token(&self, token: AuthToken) {
        self.valid_tokens.write().await.insert(token);
    }

    /// Remove token (e.g., after disconnect or session expiry)
    #[allow(dead_code)]
    pub async fn remove_token(&self, token: &AuthToken) {
        self.valid_tokens.write().await.remove(token);
    }

    /// Validate token
    ///
    /// Returns true if token is in the valid set.
    ///
    /// **Security Note**: See module-level docs about timing attack consideration.
    #[allow(dead_code)]
    pub async fn validate(&self, token: &AuthToken) -> bool {
        self.valid_tokens.read().await.contains(token)
    }

    /// Generate and add new token
    pub async fn generate_token(&self) -> AuthToken {
        let token = AuthToken::generate();
        self.add_token(token).await; // Must await the async add_token
        token
    }

    /// Get count of valid tokens
    #[allow(dead_code)]
    pub async fn token_count(&self) -> usize {
        self.valid_tokens.read().await.len()
    }

    /// Clear all tokens (e.g., for testing or admin reset)
    #[allow(dead_code)]
    pub async fn clear(&self) {
        self.valid_tokens.write().await.clear();
    }
}

impl Default for TokenStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_token_store_new() {
        let store = TokenStore::new();
        assert_eq!(store.token_count().await, 0);
    }

    #[tokio::test]
    async fn test_add_token() {
        let store = TokenStore::new();
        let token = AuthToken::generate();
        store.add_token(token).await;
        assert_eq!(store.token_count().await, 1);
    }

    #[tokio::test]
    async fn test_validate_valid_token() {
        let store = TokenStore::new();
        let token = AuthToken::generate();
        store.add_token(token).await;
        assert!(store.validate(&token).await);
    }

    #[tokio::test]
    async fn test_validate_invalid_token() {
        let store = TokenStore::new();
        let token1 = AuthToken::generate();
        let token2 = AuthToken::generate();
        store.add_token(token1).await;
        assert!(!store.validate(&token2).await);
    }

    #[tokio::test]
    async fn test_remove_token() {
        let store = TokenStore::new();
        let token = AuthToken::generate();
        store.add_token(token).await;
        assert_eq!(store.token_count().await, 1);
        store.remove_token(&token).await;
        assert_eq!(store.token_count().await, 0);
        assert!(!store.validate(&token).await);
    }

    #[tokio::test]
    async fn test_generate_token() {
        let store = TokenStore::new();
        let token = store.generate_token().await;
        assert!(store.validate(&token).await);
        assert_eq!(store.token_count().await, 1);
    }

    #[tokio::test]
    async fn test_clear_tokens() {
        let store = TokenStore::new();
        store.generate_token().await;
        store.generate_token().await;
        assert_eq!(store.token_count().await, 2);
        store.clear().await;
        assert_eq!(store.token_count().await, 0);
    }

    #[tokio::test]
    async fn test_clone_token_store() {
        let store1 = TokenStore::new();
        let token = AuthToken::generate();
        store1.add_token(token).await;

        let store2 = store1.clone();
        assert!(store2.validate(&token).await);
    }
}
