# Debug Report: "Client Already Initialized" Error

**Date**: 2026-01-09 23:58
**File**: `crates/mobile_bridge/src/api.rs`
**Severity**: High (blocks reconnection after failed attempt)
**Status**: Root Cause Identified

---

## Executive Summary

**Problem**: iOS app cannot reconnect after first connection attempt (failed or successful) due to `OnceCell` being immutable after first initialization.

**Root Cause**: `OnceCell` design prevents clearing/reinitializing the global `QUIC_CLIENT` static variable, making it impossible to:
1. Reconnect after a failed connection attempt
2. Reconnect after disconnection
3. Recover from connection errors without app restart

**Impact**: Users must force-quit and restart the entire iOS app to attempt a new connection.

**Solution**: Replace `OnceCell` with `RwLock<Option<Arc<Mutex<QuicClient>>>>` to allow reinitialization.

---

## Technical Analysis

### Current Implementation (BROKEN)

**File**: `crates/mobile_bridge/src/api.rs:38`

```rust
static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();
```

**Key Problems**:

1. **OnceCell is immutable after first set**
   - `OnceCell::set()` can only succeed once
   - Subsequent calls return `Err`
   - No method to clear/reset the cell

2. **Check prevents reconnection** (lines 74-79)
   ```rust
   if QUIC_CLIENT.get().is_some() {
       return Err("Client already initialized. Please restart app to reset.".to_string());
   }
   ```

3. **Disconnect doesn't clear the cell** (lines 166-172)
   ```rust
   pub async fn disconnect_from_host() -> Result<(), String> {
       let client_arc = QUIC_CLIENT.get()
           .ok_or_else(|| "Not connected".to_string())?;

       let mut client = client_arc.lock().await;
       client.disconnect().await  // Only closes connection, doesn't clear OnceCell
   }
   ```

### Connection Lifecycle Analysis

**Scenario 1: Failed First Connection**
```
1. User scans QR → connect_to_host() called
2. init_quic_client() → OnceCell::set() succeeds (first time)
3. client.connect() fails (network error, wrong fingerprint, etc.)
4. User tries to connect again → ERROR: "Client already initialized"
5. User MUST restart app
```

**Scenario 2: Disconnect and Reconnect**
```
1. User connects successfully → OnceCell set
2. User taps Disconnect → disconnect_from_host() closes connection
3. OnceCell still contains the client (not cleared!)
4. User tries to reconnect → ERROR: "Client already initialized"
5. User MUST restart app
```

### Why OnceCell Was Chosen

From the code history (Phase 04.1 fix):
- **Problem**: `static mut QUIC_CLIENT` caused undefined behavior
- **Solution**: `OnceCell<Arc<Mutex<QuicClient>>>` eliminated unsafe code
- **Trade-off**: Lost ability to reinitialize (not considered at the time)

**Reference**: `plans/260107-1648-fix-critical-ub-fingerprint-leak/plan.md`

---

## Proposed Solution

### Replace OnceCell with RwLock<Option<>>

**New Design**:
```rust
static QUIC_CLIENT: RwLock<Option<Arc<Mutex<QuicClient>>>> = RwLock::new(None);
```

**Benefits**:
1. ✅ Thread-safe access (RwLock)
2. ✅ Clearable (can set back to None)
3. ✅ Reinitializable (can create new client)
4. ✅ No unsafe code
5. ✅ Allows reconnection after failure/disconnect

**Implementation Changes**:

#### 1. connect_to_host() - Allow reconnection
```rust
pub async fn connect_to_host(
    host: String,
    port: u16,
    auth_token: String,
    fingerprint: String,
) -> Result<(), String> {
    init_crypto_provider();

    // NEW: Check if already connected, not just initialized
    let mut guard = QUIC_CLIENT.write().await;

    if let Some(client_arc) = guard.as_ref() {
        let client = client_arc.lock().await;
        if client.is_connected().await {
            return Err("Already connected to a host. Disconnect first.".to_string());
        }
        // Not connected, clear and reconnect
    }

    // Create new client
    let client = QuicClient::new(fingerprint);
    client.connect(host, port, auth_token).await?;
    *guard = Some(Arc::new(Mutex::new(client)));

    Ok(())
}
```

#### 2. disconnect_from_host() - Clear the client
```rust
pub async fn disconnect_from_host() -> Result<(), String> {
    let mut guard = QUIC_CLIENT.write().await;

    if let Some(client_arc) = guard.take() {  // take() removes from Option
        let mut client = client_arc.lock().await;
        client.disconnect().await?;
    }

    Ok(())
}
```

#### 3. Helper functions - Update access pattern
```rust
pub async fn receive_terminal_event() -> Result<TerminalEvent, String> {
    let guard = QUIC_CLIENT.read().await;
    let client_arc = guard.as_ref()
        .ok_or_else(|| "Not connected".to_string())?;
    let client = client_arc.lock().await;
    client.receive_event().await
}
```

---

## Test Plan

### Unit Tests to Add

```rust
#[tokio::test]
async fn test_reconnect_after_failure() {
    // First connection attempt should fail
    let result = connect_to_host(
        "invalidhost".to_string(),
        8443,
        "invalid_token".to_string(),
        "AA:BB:CC".to_string()
    ).await;
    assert!(result.is_err());

    // Second attempt should succeed
    let result = connect_to_host(
        "127.0.0.1".to_string(),
        8443,
        valid_token.to_hex(),
        valid_fingerprint
    ).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_disconnect_and_reconnect() {
    // Connect
    connect_to_host(...).await.unwrap();

    // Verify connected
    assert!(is_connected().await);

    // Disconnect
    disconnect_from_host().await.unwrap();

    // Verify not connected
    assert!(!is_connected().await);

    // Reconnect should succeed
    connect_to_host(...).await.unwrap();
    assert!(is_connected().await);
}

#[tokio::test]
async fn test_prevent_double_connection() {
    // First connection
    connect_to_host(...).await.unwrap();
    assert!(is_connected().await);

    // Second connection should fail (already connected)
    let result = connect_to_host(...).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Already connected"));
}
```

---

## Migration Path

### Phase 1: Add RwLock Implementation (Non-Breaking)
1. Add new static variable `QUIC_CLIENT_V2: RwLock<Option<...>>`
2. Implement new functions with `_v2` suffix
3. Keep old OnceCell implementation for compatibility
4. Add comprehensive tests

### Phase 2: Migrate All Callers
1. Update `connect_to_host()` to use new implementation
2. Update all helper functions (`receive_terminal_event`, etc.)
3. Update Flutter/Dart bindings if needed

### Phase 3: Remove Old Code
1. Remove old `QUIC_CLIENT` OnceCell
2. Remove `_v2` suffixes
3. Update documentation

---

## Alternatives Considered

### Alternative 1: Keep OnceCell, Add Reset Function
**Status**: ❌ Not feasible
**Reason**: OnceCell has no `take()` or `clear()` method by design

### Alternative 2: Use lazy_static
**Status**: ❌ Deprecated
**Reason**: OnceCell is the modern std replacement for lazy_static

### Alternative 3: Use std::sync::Once + RwLock
**Status**: ⚠️ Possible but unnecessary
**Reason**: RwLock<Option<>> already provides lazy initialization pattern

### Alternative 4: Keep Current Behavior (Force Restart)
**Status**: ❌ Unacceptable UX
**Reason**: Force-quitting iOS app between connection attempts is terrible UX

---

## Questions Unresolved

1. **Flutter State Management**
   - Does Flutter app expect `connect_to_host()` to be idempotent?
   - Are there Flutter-side caches that also need clearing?

2. **Thread Safety Analysis**
   - OnceCell uses atomic operations (faster)
   - RwLock uses mutex (slower but more flexible)
   - **Question**: Will RwLock contention be an issue with Flutter's thread model?

3. **Error Message UX**
   - Current: "Client already initialized. Please restart app to reset."
   - Proposed: "Already connected to a host. Disconnect first."
   - **Question**: Should we add "force disconnect" button in Flutter UI?

4. **Connection State Tracking**
   - Current: `QuicClient.is_connected()` checks `connection.close_reason()`
   - **Question**: Is this sufficient? Do we need explicit state enum (Connecting/Connected/Disconnected/Error)?

---

## Files to Modify

| File | Lines | Change |
|------|-------|--------|
| `crates/mobile_bridge/src/api.rs` | 38 | Replace OnceCell with RwLock<Option<>> |
| `crates/mobile_bridge/src/api.rs` | 65-91 | Update `connect_to_host()` logic |
| `crates/mobile_bridge/src/api.rs` | 166-172 | Update `disconnect_from_host()` to clear client |
| `crates/mobile_bridge/src/api.rs` | 101-107 | Update `receive_terminal_event()` access pattern |
| `crates/mobile_bridge/src/api.rs` | 114-120 | Update `send_terminal_command()` access pattern |
| `crates/mobile_bridge/src/api.rs` | 133-139 | Update `send_raw_input()` access pattern |
| `crates/mobile_bridge/src/api.rs` | 153-159 | Update `resize_pty()` access pattern |
| `crates/mobile_bridge/src/api.rs` | 178-185 | Update `is_connected()` access pattern |
| `crates/mobile_bridge/src/api.rs` | ~50 | Add new unit tests |
| `docs/code-standards.md` | ~10 | Update code examples |

---

## Timeline Estimate

| Task | Time |
|------|------|
| Implement RwLock<Option<>> | 30 min |
| Update all 7 helper functions | 45 min |
| Add unit tests | 45 min |
| Test with iOS app | 30 min |
| Update documentation | 15 min |
| **Total** | **~3 hours** |

---

## References

- **Original Fix**: `plans/260107-1648-fix-critical-ub-fingerprint-leak/plan.md`
- **Code Standards**: `docs/code-standards.md` (lines 237-255)
- **System Architecture**: `docs/system-architecture.md` (lines 927-960)
- **Phase 04 Implementation**: `crates/mobile_bridge/src/api.rs` (Phase 04.1)

---

## Conclusion

**Root cause identified**: OnceCell's design prevents reinitialization, making reconnection impossible without app restart.

**Recommended action**: Replace OnceCell with RwLock<Option<>> to allow reconnection while maintaining thread safety.

**Priority**: High - Blocks core UX flow (retry connection after failure).

**Risk**: Low - Well-tested pattern, no unsafe code, minimal API surface change.
