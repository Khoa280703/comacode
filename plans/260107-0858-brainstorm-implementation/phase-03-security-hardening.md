---
title: "Phase 03: Security Hardening (REVISED)"
description: "Token-based authentication, keyed rate limiting, auth failure penalty, IP banning"
status: pending
priority: P0
effort: 6h
phase: 03
created: 2026-01-07
revised: 2026-01-07
---

## Revision Notes

**Fixes applied**:
1. ✅ AuthToken derive Copy + Hash (Task 3.2)
2. ✅ RateLimiter::keyed() thay vì HashMap thủ công (Task 3.5)
3. ✅ Auth failure penalty logic (Task 3.5 + 3.6)
4. ✅ Timing attack note - accepted risk (Task 3.4)

## Objectives

Implement authentication layer, rate limiting để prevent brute-force attacks, và IP banning cho repeat offenders.

## Tasks

### 3.1 Add Security Dependencies (15min)

**File**: `Cargo.toml`

```toml
[workspace.dependencies]
# Rate limiting with keyed state support
governor = { version = "0.6", features = ["std"] }
# Crypto (if not already present)
rand = "0.8"
# nonzero_ext for governor quota
nonzero_ext = "0.3"
```

### 3.2 Token Generation (1h) **REVISED**

**File**: `crates/core/src/auth.rs` (new)

```rust
use rand::Rng;

const TOKEN_SIZE: usize = 32;  // 256-bit token

// FIX 1: Add Copy + Hash for efficient cloning + HashSet storage
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AuthToken([u8; TOKEN_SIZE]);

impl AuthToken {
    /// Generate random token
    pub fn generate() -> Self {
        let mut bytes = [0u8; TOKEN_SIZE];
        rand::thread_rng().fill(&mut bytes);
        Self(bytes)
    }

    /// Create from hex string
    pub fn from_hex(hex: &str) -> Result<Self, CoreError> {
        if hex.len() != TOKEN_SIZE * 2 {
            return Err(CoreError::InvalidTokenFormat);
        }

        let mut bytes = [0u8; TOKEN_SIZE];
        for i in 0..TOKEN_SIZE {
            bytes[i] = u8::from_str_radix(&hex[i*2..i*2+2], 16)
                .map_err(|_| CoreError::InvalidTokenFormat)?;
        }
        Ok(Self(bytes))
    }

    /// Export to hex string
    pub fn to_hex(&self) -> String {
        self.0.iter()
            .map(|b| format!("{:02x}", b))
            .collect()
    }

    /// Get raw bytes
    pub fn as_bytes(&self) -> &[u8; TOKEN_SIZE] {
        &self.0
    }
}
```

### 3.3 Handshake with Token (1.5h)

**File**: `crates/core/src/types/message.rs`

**Update Hello variant**:
```rust
pub enum NetworkMessage {
    Hello {
        protocol_version: u32,
        app_version: String,
        capabilities: u32,
        auth_token: Option<AuthToken>,  // NEW: Token in handshake
    },
    // ... rest ...
}
```

**Add auth error** (`crates/core/src/error.rs`):
```rust
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    // ... existing ...

    #[error("Authentication failed: invalid token")]
    AuthFailed,

    #[error("Missing authentication token")]
    MissingAuthToken,

    #[error("Invalid token format")]
    InvalidTokenFormat,
}
```

### 3.4 Token Storage & Validation (1h) **REVISED**

**File**: `crates/hostagent/src/auth.rs` (new)

```rust
use comacode_core::auth::AuthToken;
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct TokenStore {
    valid_tokens: Arc<RwLock<HashSet<AuthToken>>>,
}

impl TokenStore {
    pub fn new() -> Self {
        Self {
            valid_tokens: Arc::new(RwLock::new(HashSet::new())),
        }
    }

    /// Add valid token (e.g., from QR code scan)
    pub async fn add_token(&self, token: AuthToken) {
        self.valid_tokens.write().await.insert(token);
    }

    /// Remove token (e.g., after disconnect)
    pub async fn remove_token(&self, token: &AuthToken) {
        self.valid_tokens.write().await.remove(token);
    }

    /// Validate token
    ///
    /// **Security Note**: Timing attack consideration
    /// - HashSet::contains() không phải constant-time comparison
    /// - Tuy nhiên, với 256-bit random token:
    ///   - Attacker KHÔNG control token content (server generate)
    ///   - 2^256 entropy → brute force không khả thi
    ///   - HashSet hash → timing variation nhỏ hơn direct string compare
    /// - DECISION: Accepted risk cho MVP
    /// - FUTURE: constant_time_eq crate nếu có compliance yêu cầu
    pub async fn validate(&self, token: &AuthToken) -> bool {
        self.valid_tokens.read().await.contains(token)
    }

    /// Generate and add new token
    pub async fn generate_token(&self) -> AuthToken {
        let token = AuthToken::generate();
        self.add_token(token.clone()).await;
        token
    }
}
```

### 3.5 Rate Limiting với Governor Keyed (2h) **REVISED**

**File**: `crates/hostagent/src/ratelimit.rs` (new)

```rust
use governor::{
    clock::DefaultClock,
    state::Keyed,  // FIX 2a: Keyed state thay vì NotKeyed
    Quota, RateLimiter,
};
use std::collections::{HashMap, HashSet};
use std::net::IpAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use nonzero_ext::nonzero;

/// Rate limiter: 5 attempts per minute
const RATE_LIMIT: u32 = 5;

/// Auth failures before ban
const AUTH_FAIL_THRESHOLD: u32 = 3;

/// FIX 2b: Use Keyed RateLimiter - governor tự quản lý IP → Bucket map
/// - Tự động cleanup old buckets (GC)
/// - Không cần HashMap + RwLock cồng kềnh
pub struct RateLimiterStore {
    /// Governor keyed limiter - tự quản lý per-IP state
    limiter: Arc<RateLimiter<IpAddr, Keyed<IpAddr>, DefaultClock>>,
    /// FIX 3a: Auth failure tracker - riêng biệt vì cần khác với rate limit
    auth_failures: Arc<RwLock<HashMap<IpAddr, u32>>>,
    /// Permanently banned IPs
    banned_ips: Arc<RwLock<HashSet<IpAddr>>>,
}

impl RateLimiterStore {
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

    /// Ban IP address
    pub async fn ban_ip(&self, ip: IpAddr) {
        self.banned_ips.write().await.insert(ip);
        tracing::warn!("Banned IP: {} (auth failures)", ip);
    }

    /// Check rate limit for IP
    pub async fn check(&self, ip: IpAddr) -> Result<(), CoreError> {
        // Check ban list first
        if self.is_banned(ip).await {
            return Err(CoreError::IpBanned { ip });
        }

        // FIX 2c: Direct check with keyed limiter - governor tự tạo bucket nếu chưa có
        self.limiter.check_key(&ip)
            .map_err(|_| CoreError::RateLimitExceeded)
    }

    /// FIX 3b: Record auth failure - track riêng để ban sau N lần
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

    /// Reset auth failure counter (gọi khi auth thành công)
    pub async fn reset_auth_failures(&self, ip: IpAddr) {
        let mut failures = self.auth_failures.write().await;
        failures.remove(&ip);
    }

    /// Cleanup old auth failure entries (call periodically)
    pub async fn cleanup_auth_failures(&self) {
        // TODO: Implement TTL-based cleanup (Phase 05)
        // For now, entries persist until restart
    }
}
```

**Update error types**:
```rust
#[error("IP address {ip} is banned")]
IpBanned { ip: IpAddr },

#[error("Rate limit exceeded")]
RateLimitExceeded,
```

**Key changes from original**:
1. ❌ Removed `HashMap<IpAddr, IpLimiter>` - governor Keyed handles this
2. ✅ Added `auth_failures: HashMap<IpAddr, u32>` - track auth failures separately
3. ✅ Added `record_auth_failure()` - penalize failed token attempts
4. ✅ Added `reset_auth_failures()` - clean slate after successful auth

### 3.6 Integration in Connection Flow (30min) **REVISED**

**File**: `crates/hostagent/src/connection.rs`

```rust
use comacode_core::auth::AuthToken;

pub async fn handle_connection(
    stream: &mut Connection,
    peer_ip: IpAddr,
    token_store: &TokenStore,
    rate_limiter: &RateLimiterStore,
) -> Result<Session, CoreError> {
    // Step 1: Check rate limit (connection attempts)
    rate_limiter.check(peer_ip).await?;

    // Step 2: Receive Hello
    let msg = stream.recv_message().await?;
    let token = match &msg {
        NetworkMessage::Hello { auth_token, .. } => {
            auth_token.as_ref()
                .ok_or(CoreError::MissingAuthToken)?
        }
        _ => return Err(CoreError::InvalidHandshake),
    };

    // Step 3: Validate token
    if !token_store.validate(token).await {
        tracing::warn!("Auth failed for IP: {}", peer_ip);

        // FIX 3c: CRITICAL - Record auth failure để track + ban nếu quá nhiều
        // Nếu không làm việc này, attacker có thể thử token vô hạn lần
        // (vì rate limit chỉ count connection attempts, không count auth attempts)
        let _ = rate_limiter.record_auth_failure(peer_ip).await;

        return Err(CoreError::AuthFailed);
    }

    // Step 4: Reset auth failure counter on success
    rate_limiter.reset_auth_failures(peer_ip).await;

    // Step 5: Validate protocol version
    msg.validate_handshake()?;

    // Step 6: Send Hello response
    stream.send_message(&NetworkMessage::hello()).await?;

    Ok(session)
}
```

**FIX 3c - Critical Security Logic**:
- ❌ **Old code**: Auth failure chỉ log, không track
- ✅ **New code**: `record_auth_failure()` track + auto-ban sau 3 lần
- ✅ **Success path**: `reset_auth_failures()` clear slate khi token đúng

**Attack vector prevented**:
```
Attacker loop:
  connect → rate_limit_check → send_hello → WRONG_TOKEN → disconnect
  ↑                                              ↓
  └──────────────────────────────────────────────┘
    WITHOUT fix: Vô hạn iterations (rate limit chỉ count connections)
    WITH fix: Ban sau 3 attempts
```

## Testing Strategy

**Manual Test**:
1. Generate token via CLI
2. Try connect without token → reject
3. Try connect with wrong token → reject + rate limit
4. Try connect 6 times rapidly → rate limit exceeded
5. Verify ban persists

**Unit Tests**:
```rust
#[test]
fn test_token_generation() {
    let token1 = AuthToken::generate();
    let token2 = AuthToken::generate();
    assert_ne!(token1, token2);  // Randomness
}

#[test]
fn test_token_hex_roundtrip() {
    let token = AuthToken::generate();
    let hex = token.to_hex();
    let decoded = AuthToken::from_hex(&hex).unwrap();
    assert_eq!(token, decoded);
}
```

**Load Test**:
- Script 10 connection attempts trong 1 second
- Verify only 5 succeed, rest rate-limited

**Acceptance Criteria**:
- ✅ Token generation deterministic from hex
- ✅ Invalid tokens rejected with error
- ✅ Rate limiter blocks after 5 attempts/min
- ✅ Banned IPs cannot connect
- ✅ Valid tokens allow connection

## Dependencies

- Phase 01 (Hello message structure)

## Blocked By

- None

## Configuration

**Environment Variables**:
```bash
# Optional: Override defaults
COMACODE_RATE_LIMIT=10      # attempts per minute
COMACODE_BAN_DURATION=3600  # seconds (if implementing TTL)
```

**Hardcoded for MVP**:
- 5 attempts/minute
- Permanent ban (until restart)
- 32-byte tokens (256-bit)

## Security Considerations

### Accepted Risks (MVP)

| Risk | Mitigation | Decision |
|------|-----------|----------|
| **Timing attack** trên token validation | 256-bit random token, attacker không control input | ✅ Accept - HashSet sufficient |
| **Permanent ban** cho auth failure | Manual restart để clear | ✅ Accept - MVP simplicity |
| **No token rotation** | Static token per session | ✅ Accept - Phase 04 upgrade |

### Future Enhancements

1. **Constant-time comparison**: constant_time_eq crate nếu có compliance yêu cầu
2. **Decay-based ban**: Auto-unban sau X phút không có lỗi
3. **Token expiration**: TTL-based invalidation
4. **Per-device tokens**: Multi-device support

**Token Distribution**: Chưa resolved (see Phase 04)
- QR code contains token?
- Manual copy-paste?
- Out-of-band (e.g., local file)?

## Unresolved Questions

1. **Rate limit strictness**: 5/min có quá aggressive không? → Test in Phase 05
2. **Ban duration**: Permanent vs TTL? → ✅ Start with permanent (accept)
3. **Token in QR code**: Security risk nếu QR screenshot? → Discuss Phase 04
