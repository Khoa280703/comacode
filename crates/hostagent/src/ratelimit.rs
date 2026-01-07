//! Rate limiting and IP banning for Phase E03 Security Hardening
//!
//! # RateLimiterStore
//!
//! Uses governor crate's Keyed state for per-IP rate limiting.
//! Tracks auth failures separately to ban repeat offenders.
//!
//! ## Architecture
//!
//! - **Keyed RateLimiter**: Governor automatically manages IP → bucket map
//! - **Auth Failures**: Separate HashMap tracks failed auth attempts
//! - **Ban List**: HashSet of permanently banned IPs
//!
//! ## Keyed vs NotKeyed (Phase E03 Fix)
//!
//! **Before (Wrong)**: HashMap<IpAddr, RateLimiter<NotKeyed, ...>>
//! - Manual map management
//! - No automatic cleanup
//! - Need RwLock for map access
//!
//! **After (Correct)**: RateLimiter<IpAddr, Keyed<IpAddr>, ...>
//! - Governor manages IP → bucket automatically
//! - Automatic GC of old buckets
//! - Direct check_key() API

use comacode_core::CoreError;
use governor::{
    clock::DefaultClock,
    state::keyed::DefaultKeyedStateStore,
    Quota, RateLimiter,
};
use std::collections::{HashMap, HashSet};
use std::net::IpAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use nonzero_ext::nonzero;

/// Rate limit: 5 connection attempts per minute
const RATE_LIMIT: u32 = 5;

/// Auth failures before permanent ban
const AUTH_FAIL_THRESHOLD: u32 = 3;

/// Rate limiting and IP banning store
///
/// Uses governor's keyed rate limiter for per-IP connection tracking.
/// Tracks auth failures separately to ban after repeated failed attempts.
#[derive(Clone)]
#[allow(dead_code)]
pub struct RateLimiterStore {
    /// Governor keyed limiter - auto-manages per-IP buckets
    limiter: Arc<RateLimiter<IpAddr, DefaultKeyedStateStore<IpAddr>, DefaultClock>>,
    /// Auth failure tracker - separate from rate limit
    auth_failures: Arc<RwLock<HashMap<IpAddr, u32>>>,
    /// Permanently banned IPs
    banned_ips: Arc<RwLock<HashSet<IpAddr>>>,
}

#[allow(dead_code)]
impl RateLimiterStore {
    /// Create new rate limiter store
    pub fn new() -> Self {
        let quota = Quota::per_minute(nonzero!(RATE_LIMIT));
        Self {
            limiter: Arc::new(RateLimiter::keyed(quota)),
            auth_failures: Arc::new(RwLock::new(HashMap::new())),
            banned_ips: Arc::new(RwLock::new(HashSet::new())),
        }
    }

    /// Check if IP is banned
    pub async fn is_banned(&self, ip: IpAddr) -> bool {
        self.banned_ips.read().await.contains(&ip)
    }

    /// Ban IP address permanently
    pub async fn ban_ip(&self, ip: IpAddr) {
        self.banned_ips.write().await.insert(ip);
        tracing::warn!("Banned IP: {} (auth failures)", ip);
    }

    /// Check rate limit for IP
    ///
    /// Returns error if:
    /// - IP is banned
    /// - Rate limit exceeded
    pub async fn check(&self, ip: IpAddr) -> Result<(), CoreError> {
        // Check ban list first
        if self.is_banned(ip).await {
            return Err(CoreError::IpBanned { ip });
        }

        // Check rate limit - governor creates bucket automatically
        self.limiter.check_key(&ip)
            .map_err(|_| CoreError::RateLimitExceeded)
    }

    /// Record authentication failure
    ///
    /// Tracks failed auth attempts and bans IP after threshold.
    /// This is separate from rate limiting to prevent brute force token attacks.
    ///
    /// # Security Rationale
    ///
    /// Without this, attacker could:
    /// - Connect → rate_limit_check → send_hello → WRONG_TOKEN → disconnect
    /// - Repeat infinitely (rate limit only counts connections, not auth attempts)
    ///
    /// With this, attacker gets banned after 3 failed token attempts.
    pub async fn record_auth_failure(&self, ip: IpAddr) -> Result<(), CoreError> {
        let mut failures = self.auth_failures.write().await;
        let count = failures.entry(ip).or_insert(0);
        *count += 1;

        tracing::warn!("Auth failure count for {}: {}", ip, count);

        if *count >= AUTH_FAIL_THRESHOLD {
            drop(failures);
            self.ban_ip(ip).await;
            Err(CoreError::IpBanned { ip })
        } else {
            Ok(())
        }
    }

    /// Reset auth failure counter (call on successful auth)
    pub async fn reset_auth_failures(&self, ip: IpAddr) {
        self.auth_failures.write().await.remove(&ip);
    }

    /// Get current auth failure count for IP
    pub async fn auth_failure_count(&self, ip: IpAddr) -> u32 {
        self.auth_failures.read().await.get(&ip).copied().unwrap_or(0)
    }

    /// Get count of banned IPs
    pub async fn banned_count(&self) -> usize {
        self.banned_ips.read().await.len()
    }

    /// Cleanup old auth failure entries
    ///
    /// TODO: Implement TTL-based cleanup (Phase 05)
    /// For now, entries persist until restart
    pub async fn cleanup_auth_failures(&self) {
        // Future: Remove entries older than X minutes
    }
}

impl Default for RateLimiterStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Ipv4Addr, Ipv6Addr};

    fn test_ip_v4() -> IpAddr {
        IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1))
    }

    fn test_ip_v6() -> IpAddr {
        IpAddr::V6(Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 1))
    }

    #[tokio::test]
    async fn test_rate_limiter_new() {
        let store = RateLimiterStore::new();
        assert_eq!(store.banned_count().await, 0);
        assert!(!store.is_banned(test_ip_v4()).await);
    }

    #[tokio::test]
    async fn test_check_rate_limit_under_limit() {
        let store = RateLimiterStore::new();
        let ip = test_ip_v4();

        // Should allow 5 requests
        for _ in 0..5 {
            assert!(store.check(ip).await.is_ok());
        }
    }

    #[tokio::test]
    async fn test_check_rate_limit_exceeded() {
        let store = RateLimiterStore::new();
        let ip = test_ip_v4();

        // Exhaust rate limit (5 attempts)
        for _ in 0..5 {
            let _ = store.check(ip).await;
        }

        // Next request should fail
        let result = store.check(ip).await;
        assert!(matches!(result, Err(CoreError::RateLimitExceeded)));
    }

    #[tokio::test]
    async fn test_ban_ip() {
        let store = RateLimiterStore::new();
        let ip = test_ip_v4();

        assert!(!store.is_banned(ip).await);
        store.ban_ip(ip).await;
        assert!(store.is_banned(ip).await);

        // Banned IP should fail check
        let result = store.check(ip).await;
        assert!(matches!(result, Err(CoreError::IpBanned { .. })));
    }

    #[tokio::test]
    async fn test_auth_failure_tracking() {
        let store = RateLimiterStore::new();
        let ip = test_ip_v4();

        assert_eq!(store.auth_failure_count(ip).await, 0);

        // First failure
        let result = store.record_auth_failure(ip).await;
        assert!(result.is_ok());
        assert_eq!(store.auth_failure_count(ip).await, 1);

        // Second failure
        let result = store.record_auth_failure(ip).await;
        assert!(result.is_ok());
        assert_eq!(store.auth_failure_count(ip).await, 2);

        // Third failure - should ban
        let result = store.record_auth_failure(ip).await;
        assert!(matches!(result, Err(CoreError::IpBanned { .. })));
        assert!(store.is_banned(ip).await);
    }

    #[tokio::test]
    async fn test_reset_auth_failures() {
        let store = RateLimiterStore::new();
        let ip = test_ip_v4();

        store.record_auth_failure(ip).await.unwrap();
        assert_eq!(store.auth_failure_count(ip).await, 1);

        store.reset_auth_failures(ip).await;
        assert_eq!(store.auth_failure_count(ip).await, 0);
    }

    #[tokio::test]
    async fn test_multiple_ips_tracked_separately() {
        let store = RateLimiterStore::new();
        let ip1 = test_ip_v4();
        let ip2 = test_ip_v6();

        store.record_auth_failure(ip1).await.unwrap();
        assert_eq!(store.auth_failure_count(ip1).await, 1);
        assert_eq!(store.auth_failure_count(ip2).await, 0);

        store.record_auth_failure(ip2).await.unwrap();
        assert_eq!(store.auth_failure_count(ip1).await, 1);
        assert_eq!(store.auth_failure_count(ip2).await, 1);
    }

    #[tokio::test]
    async fn test_clone_store() {
        let store1 = RateLimiterStore::new();
        let ip = test_ip_v4();
        let store2 = store1.clone();

        store1.ban_ip(ip).await;
        assert!(store2.is_banned(ip).await);
    }
}
