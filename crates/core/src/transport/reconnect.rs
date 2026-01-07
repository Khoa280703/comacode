//! Reconnection logic with exponential backoff
//!
//! This module provides automatic reconnection with exponential backoff
//! for handling temporary network failures.

use quinn::{Endpoint, Connection};
use std::time::Duration;
use tokio::time::sleep;

use crate::{CoreError, Result};

/// Reconnection configuration
#[derive(Debug, Clone)]
pub struct ReconnectConfig {
    /// Maximum backoff time between attempts
    pub max_backoff: Duration,
    /// Initial backoff time
    pub initial_backoff: Duration,
    /// Maximum number of reconnection attempts (None = infinite)
    pub max_attempts: Option<usize>,
}

impl Default for ReconnectConfig {
    fn default() -> Self {
        Self {
            max_backoff: Duration::from_secs(30),
            initial_backoff: Duration::from_secs(1),
            max_attempts: Some(10),
        }
    }
}

/// Attempt reconnection with exponential backoff
///
/// # Arguments
/// * `endpoint` - QUIC endpoint to use for connection
/// * `host` - Target hostname or IP (used as both address and SNI server name)
/// * `port` - Target port
/// * `config` - Reconnection configuration
///
/// # Behavior
/// 1. Try to connect immediately
/// 2. On failure, wait with exponential backoff (1s, 2s, 4s, ..., max 30s)
/// 3. Retry up to max_attempts (or forever if None)
/// 4. Return connection on success
///
/// # Returns
/// * `Ok(Connection)` - Successfully reconnected
/// * `Err(CoreError::MaxReconnectAttemptsReached)` - Exceeded max attempts
/// * `Err(...)` - Other error
pub async fn reconnect_with_backoff(
    endpoint: &Endpoint,
    host: &str,
    port: u16,
    config: ReconnectConfig,
) -> Result<Connection> {
    let mut backoff = config.initial_backoff;
    let mut attempt = 0;

    loop {
        attempt += 1;

        // Validate host is not empty
        if host.is_empty() {
            return Err(CoreError::Connection("Host cannot be empty".to_string()));
        }

        // Try to connect
        let addr = format!("{}:{}", host, port)
            .parse::<std::net::SocketAddr>()
            .map_err(|e| CoreError::Connection(format!("Invalid address: {}", e)))?;

        let connecting = endpoint.connect(addr, host)
            .map_err(|e| CoreError::Connection(format!("Failed to initiate connection: {}", e)))?;

        match connecting.await {
            Ok(conn) => {
                tracing::info!("Reconnected after {} attempts", attempt);
                return Ok(conn);
            }
            Err(e) => {
                // Check if we've exceeded max attempts
                if let Some(max) = config.max_attempts {
                    if attempt >= max {
                        tracing::error!("Max reconnection attempts ({}) reached", max);
                        return Err(CoreError::Connection(format!(
                            "Max reconnection attempts ({}) reached. Last error: {}",
                            max, e
                        )));
                    }
                }

                tracing::warn!("Reconnect attempt {} failed: {}, retrying in {:?}",
                    attempt, e, backoff);

                // Wait before retrying (exponential backoff)
                sleep(backoff).await;

                // Exponential backoff: double the backoff, capped at max_backoff
                backoff = std::cmp::min(backoff * 2, config.max_backoff);
            }
        }
    }
}

/// Create reconnect config with custom values
pub fn reconnect_config(
    max_backoff: Duration,
    initial_backoff: Duration,
    max_attempts: Option<usize>,
) -> ReconnectConfig {
    ReconnectConfig {
        max_backoff,
        initial_backoff,
        max_attempts,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reconnect_config_default() {
        let config = ReconnectConfig::default();
        assert_eq!(config.max_backoff, Duration::from_secs(30));
        assert_eq!(config.initial_backoff, Duration::from_secs(1));
        assert_eq!(config.max_attempts, Some(10));
    }

    #[test]
    fn test_reconnect_config_custom() {
        let config = reconnect_config(
            Duration::from_secs(60),
            Duration::from_secs(2),
            Some(5),
        );
        assert_eq!(config.max_backoff, Duration::from_secs(60));
        assert_eq!(config.initial_backoff, Duration::from_secs(2));
        assert_eq!(config.max_attempts, Some(5));
    }

    #[test]
    fn test_reconnect_config_infinite_attempts() {
        let config = reconnect_config(
            Duration::from_secs(30),
            Duration::from_secs(1),
            None,
        );
        assert_eq!(config.max_attempts, None);
    }
}
