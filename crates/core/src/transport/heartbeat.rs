//! Heartbeat and timeout detection for QUIC connections
//!
//! This module provides periodic ping/pong for connection health monitoring
//! and automatic timeout detection.

use quinn::SendStream;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tokio::time::{interval, Instant};

use crate::protocol::MessageCodec;
use crate::types::NetworkMessage;
use crate::{CoreError, Result};

/// Heartbeat manager for connection health monitoring
///
/// Tracks last activity time and spawns a task to send periodic pings.
/// Uses simple timestamp-based timeout detection.
pub struct Heartbeat {
    last_activity: Arc<AtomicU64>,
    timeout: Duration,
}

impl Heartbeat {
    /// Create new heartbeat monitor
    ///
    /// # Arguments
    /// * `timeout` - Maximum idle time before considering connection dead
    pub fn new(timeout: Duration) -> Self {
        Self {
            last_activity: Arc::new(AtomicU64::new(
                Instant::now().elapsed().as_secs()
            )),
            timeout,
        }
    }

    /// Spawn heartbeat task
    ///
    /// This task:
    /// 1. Ticks every `interval`
    /// 2. Checks if idle time exceeds `timeout`
    /// 3. Sends ping if still alive
    ///
    /// # Arguments
    /// * `send` - QUIC send stream for pings
    /// * `interval` - Time between pings (e.g., 5s)
    /// * `timeout` - Maximum idle time before error
    /// * `last_activity` - Shared atomic with timestamp of last activity
    ///
    /// # Returns
    /// JoinHandle that resolves when timeout occurs or task fails
    pub fn spawn(
        mut send: SendStream,
        interval: Duration,
        timeout: Duration,
        last_activity: Arc<AtomicU64>,
    ) -> tokio::task::JoinHandle<std::result::Result<(), CoreError>> {
        tokio::spawn(async move {
            let mut ticker = interval(interval);

            loop {
                ticker.tick().await;

                // ✅ CORRECT LOGIC: Compare current timestamp with last activity timestamp
                // Both are seconds since app start - simple subtraction works
                let current_secs = Instant::now().elapsed().as_secs();
                let last_secs = last_activity.load(Ordering::Relaxed);

                // Calculate time since last activity
                let idle_secs = current_secs.saturating_sub(last_secs);

                if idle_secs > timeout.as_secs() {
                    tracing::error!("Heartbeat timeout! Last activity was {}s ago", idle_secs);
                    return Err(CoreError::Timeout(idle_secs * 1000));
                }

                // Send ping
                let msg = NetworkMessage::ping();
                match MessageCodec::encode(&msg) {
                    Ok(encoded) => {
                        if let Err(e) = send.write_all(&encoded).await {
                            tracing::error!("Failed to send ping: {}", e);
                            return Err(CoreError::Connection(e.to_string()));
                        }
                        tracing::debug!("Heartbeat sent, idle time: {}s", idle_secs);
                    }
                    Err(e) => {
                        tracing::error!("Failed to encode ping: {}", e);
                        return Err(e);
                    }
                }
            }
        })
    }

    /// Record activity (update last activity timestamp)
    ///
    /// Call this when receiving any data from the connection.
    pub fn record_activity(&self) {
        self.last_activity.store(
            Instant::now().elapsed().as_secs(),
            Ordering::Relaxed
        );
    }

    /// Get shared Arc for passing to spawn()
    pub fn shared_activity(&self) -> Arc<AtomicU64> {
        self.last_activity.clone()
    }

    /// Get current idle time in seconds
    pub fn idle_secs(&self) -> u64 {
        let current_secs = Instant::now().elapsed().as_secs();
        let last_secs = self.last_activity.load(Ordering::Relaxed);
        current_secs.saturating_sub(last_secs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_heartbeat_new_creates_valid_state() {
        let timeout = Duration::from_secs(30);
        let heartbeat = Heartbeat::new(timeout);
        assert_eq!(heartbeat.timeout, timeout);
        assert_eq!(heartbeat.idle_secs(), 0);
    }

    #[test]
    fn test_record_activity_updates_timestamp() {
        let heartbeat = Heartbeat::new(Duration::from_secs(30));

        // Initially idle time should be ~0
        let initial_idle = heartbeat.idle_secs();
        assert!(initial_idle < 2);

        // Record activity
        heartbeat.record_activity();

        // Idle time should reset to ~0
        let new_idle = heartbeat.idle_secs();
        assert!(new_idle < 2);
    }

    #[test]
    fn test_shared_activity_returns_cloned_arc() {
        let heartbeat = Heartbeat::new(Duration::from_secs(30));
        let shared = heartbeat.shared_activity();

        // Both should point to same value
        heartbeat.record_activity();
        let secs1 = heartbeat.last_activity.load(Ordering::Relaxed);
        let secs2 = shared.load(Ordering::Relaxed);
        assert_eq!(secs1, secs2);
    }
}
