# Brainstorming: Auth Validation + Token Expiry Fix

**Ngày**: 2026-01-07
**Issues**: #1 (Auth Validation P0), #2 (Token Expiry P1)
**Status**: Solution ready, awaiting implementation

---

## Problem Statement

### Issue #1: Auth Validation Not Integrated (P0)
- `TokenStore` và `RateLimiterStore` đã implement nhưng **KHÔNG dùng**
- Client kết nối mà không cần validate token
- Security gap: toàn bộ auth system thành "bù nhìn"

### Issue #2: Token Expiry Missing (P1)
- Token lifetime = mãi mã
- Security risk: leaked token usable forever
- No cleanup mechanism

---

## Decision: Non-Breaking Approach

**Rationale**: Avoid breaking existing QR code format, mobile clients, and Hash trait.

```rust
// ✅ APPROVED: AuthToken KHÔNG đổi
pub struct AuthToken([u8; 32]);  // Still Copy + Hash

// ✅ TokenStore tracks expiry separately
pub struct TokenStore {
    valid_tokens: Arc<RwLock<HashMap<AuthToken, SystemTime>>>,  // token -> created_at
}
```

**Benefits**:
- No breaking change
- Token vẫn `Copy + Hash + Serialize`
- Expiry logic ở server side (correct)

---

## Solution #1: Auth Validation (P0)

### Location: `crates/hostagent/src/quic_server.rs`

```rust
use crate::auth::TokenStore;
use crate::ratelimit::RateLimiterStore;
use std::net::IpAddr;

impl QuicServer {
    /// Handle incoming connection - validate auth BEFORE creating session
    async fn handle_connection(
        &self,
        mut connection: Connection,
        peer_ip: IpAddr,
    ) -> Result<(), CoreError> {
        // Open bi-directional stream
        let (mut send, mut recv) = connection.accept_bi().await?;

        // Read Hello message
        let mut buf = vec![0u8; 4096];
        let n = recv.read(&mut buf).await?.ok_or(CoreError::ConnectionClosed)?;
        let msg = MessageCodec::decode(&buf[..n])?;

        match msg {
            NetworkMessage::Hello { auth_token, protocol_version, .. } => {
                // 1. Validate protocol version
                if protocol_version != PROTOCOL_VERSION {
                    self.send_error(&mut send, CoreError::ProtocolMismatch).await?;
                    return Err(CoreError::ProtocolMismatch);
                }

                // 2. VALIDATE AUTH TOKEN (Critical fix)
                let token_valid = if let Some(token) = auth_token {
                    self.token_store.validate(&token).await
                } else {
                    tracing::warn!("No token provided from IP: {}", peer_ip);
                    false
                };

                if !token_valid {
                    tracing::warn!("Auth failed for IP: {}", peer_ip);

                    // Record failure for rate limiting
                    let _ = self.rate_limiter.record_auth_failure(peer_ip).await;

                    // Send error to client
                    self.send_error(&mut send, CoreError::AuthFailed).await?;
                    return Err(CoreError::AuthFailed);
                }

                // 3. Reset auth failures on success
                self.rate_limiter.reset_auth_failures(peer_ip).await;
                tracing::info!("Client authenticated: {}", peer_ip);

                // 4. Send Hello response
                let response = NetworkMessage::Hello {
                    auth_token: None,  // Server doesn't need client token
                    protocol_version: PROTOCOL_VERSION,
                    app_version: env!("CARGO_PKG_VERSION").to_string(),
                };
                send.write_all(&MessageCodec::encode(&response)?).await?;

                // 5. Create session (continue normal flow)
                self.create_session(connection, peer_ip).await?;
                Ok(())
            }
            _ => {
                self.send_error(&mut send, CoreError::InvalidHandshake).await?;
                Err(CoreError::InvalidHandshake)
            }
        }
    }

    /// Send error message to client before closing
    async fn send_error(
        &self,
        send: &mut SendStream,
        error: CoreError,
    ) -> Result<(), CoreError> {
        // Optional: Send error details for debugging
        // For now, just close gracefully
        Ok(())
    }
}
```

### Changes Required

1. **Add imports**: `TokenStore`, `RateLimiterStore` vào `quic_server.rs`
2. **Add field**: `QuicServer` cần hold reference đến `TokenStore` và `RateLimiterStore`
3. **Add method**: `handle_connection()` với auth validation logic
4. **Wire up**: Main loop passes stores to QuicServer

---

## Solution #2: Token Expiry (P1)

### Decision: TTL = 7 days

**Rationale**:
- 24h too aggressive → user phải scan QR mỗi sáng
- 7 days balances security vs UX
- Configurable later with `--token-ttl` flag

### Location: `crates/hostagent/src/auth.rs`

```rust
use std::time::{SystemTime, Duration};

const DEFAULT_TOKEN_TTL: Duration = Duration::from_secs(7 * 24 * 60 * 60); // 7 days

pub struct TokenStore {
    // Changed: tracks (token, created_at) instead of just token
    valid_tokens: Arc<RwLock<HashMap<AuthToken, SystemTime>>>,
}

impl TokenStore {
    pub fn new() -> Self {
        Self {
            valid_tokens: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Add new token with current timestamp
    pub async fn add_token(&self, token: AuthToken) {
        let created_at = SystemTime::now();
        self.valid_tokens.write().await.insert(token, created_at);
    }

    /// Validate token AND check expiry
    pub async fn validate(&self, token: &AuthToken) -> bool {
        let tokens = self.valid_tokens.read().await;

        if let Some(created_at) = tokens.get(token) {
            // Check expiry
            match created_at.elapsed() {
                Ok(elapsed) => elapsed < DEFAULT_TOKEN_TTL,
                Err(_) => false,  // Clock went backwards? Expired.
            }
        } else {
            false  // Token not found
        }
    }

    /// Remove expired tokens (call periodically)
    pub async fn cleanup_expired(&self) -> usize {
        let mut tokens = self.valid_tokens.write().await;
        let now = SystemTime::now();

        let before = tokens.len();
        tokens.retain(|_token, created_at| {
            created_at.elapsed().unwrap_or(Duration::MAX) < DEFAULT_TOKEN_TTL
        });

        before - tokens.len()
    }

    // ... rest of methods unchanged
}
```

### Bonus: Periodic Cleanup

```rust
// In quic_server.rs main loop
tokio::spawn(async move {
    let mut interval = tokio::time::interval(Duration::from_secs(3600));  // Hourly
    loop {
        interval.tick().await;
        let cleaned = token_store.cleanup_expired().await;
        if cleaned > 0 {
            tracing::info!("Cleaned {} expired tokens", cleaned);
        }
    }
});
```

---

## Implementation Plan

### Phase 07-A: Auth Validation (1-2h)

1. Modify `QuicServer` struct:
   ```rust
   pub struct QuicServer {
       endpoint: Endpoint,
       token_store: Arc<TokenStore>,
       rate_limiter: Arc<RateLimiterStore>,
       // ...
   }
   ```

2. Update `main.rs` to pass stores:
   ```rust
   let token_store = Arc::new(TokenStore::new());
   let rate_limiter = Arc::new(RateLimiterStore::new());

   let server = QuicServer::new(cert, key, token_store, rate_limiter).await?;
   ```

3. Implement `handle_connection()` with auth validation

4. Add error response to client (nice-to-have)

### Phase 07-B: Token Expiry (1-2h)

1. Change `TokenStore::valid_tokens` type
2. Update `add_token()` to store timestamp
3. Update `validate()` to check expiry
4. Add `cleanup_expired()` method
5. Add periodic cleanup task

### Total Estimate: 2-4h

---

## Testing Checklist

**Auth Validation**:
- [ ] Valid token → connection succeeds
- [ ] Invalid token → connection rejected
- [ ] No token → connection rejected
- [ ] Expired token → connection rejected (after Phase 07-B)

**Token Expiry**:
- [ ] New token valid for 7 days
- [ ] Expired token rejected
- [ ] Cleanup task removes expired tokens
- [ ] Manual `--token-ttl` flag (optional)

**Rate Limiting** (already implemented, now integrated):
- [ ] 3 failed auth → IP banned
- [ ] Successful auth → reset counter

---

## Files to Modify

```
crates/hostagent/src/
├── quic_server.rs    # Add auth validation in handle_connection()
└── auth.rs            # Change HashMap<AuthToken, SystemTime>
```

**No changes needed**:
- `crates/core/src/auth.rs` → AuthToken struct unchanged
- `crates/core/src/types/` → NetworkMessage unchanged
- Mobile clients → No breaking change

---

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Token expiry too short | 7 days chosen, configurable later |
| Clock skew (client vs server) | Server time only, client doesn't matter |
| Memory leak from tokens | Periodic cleanup every hour |
| Auth blocks legitimate users | Clear error messages, retry mechanism |

---

## Success Criteria

1. ✅ Auth validation active in QUIC server
2. ✅ Invalid/expired tokens rejected
3. ✅ Rate limiting triggered on auth failures
4. ✅ Expired tokens auto-cleaned
5. ✅ No breaking changes to existing clients

---

## Unresolved Questions

1. **Error response format**: Should server send detailed error to client?
   - Suggestion: Simple close for MVP, add error message later

2. **Token rotation**: Should token refresh automatically?
   - Suggestion: No, manual re-scan QR for MVP

3. **Admin override**: How to unban IP?
   - Suggestion: Restart hostagent for MVP, add CLI command later

---

**Last updated**: 2026-01-07
**Status**: ✅ Ready for implementation
