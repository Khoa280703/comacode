# Debug Report: Flutter sendCommand() Blocking on iOS

**Date:** 2026-01-22 08:38
**Issue:** sendCommand() hangs indefinitely on iOS
**Severity:** Critical - blocks all terminal commands

---

## Executive Summary

**Root Cause:** iOS device running outdated Rust library (Jan 21 build) without Phase 09 background receive task pattern. Old code blocks in `receive_event()` on QUIC stream read, freezing Dart isolate and preventing `sendCommand()` from completing.

**Fix Required:** Rebuild iOS static library with current code + deploy to device.

**Status:** Code fix exists in working tree (uncommitted), but not deployed to iOS.

---

## Timeline of Events

### 2026-01-21 15:16:24
- `libmobile_bridge.a` built with **old blocking code**
- `receive_event()` does blocking `recv.read()` on QUIC stream
- No background task pattern

### 2026-01-22 (Before Incident)
- Code changes made to `quic_client.rs` and `api.rs`
- **Phase 09 background receive task pattern** implemented
- Changes **NOT committed** and **NOT rebuilt** for iOS

### During Incident
- User sends command: `ping 8.8.8.8`
- Flutter logs: `🟢 [Terminal] Sending command`
- Bridge logs: `🔵 [BridgeWrapper] sendCommand called`
- **Hangs forever** - no completion/error logs

---

## Technical Analysis

### Code Comparison

#### Old Code (DEPLOYED to iOS - Jan 21)
```rust
// quic_client.rs - receive_event() - BLOCKING
pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
    let recv_stream = self.recv_stream.as_ref()
        .ok_or_else(|| "Not connected".to_string())?;

    let mut recv = recv_stream.lock().await;
    let mut read_buf = vec![0u8; 8192];

    // 🔴 BLOCKING READ - freezes Dart isolate
    let n = recv.read(&mut read_buf).await
        .map_err(|e| format!("Failed to read from stream: {}", e))?
        .ok_or_else(|| format!("Connection closed"))?;
    // ...
}
```

#### New Code (in working tree - UNCOMMITTED)
```rust
// quic_client.rs - Phase 09 background task pattern
pub async fn receive_event(&self) -> Result<TerminalEvent, String> {
    let mut buffer = self.event_buffer.lock().await;

    if buffer.is_empty() {
        // ✅ NON-BLOCKING - returns immediately
        Ok(TerminalEvent::output_str(""))
    } else {
        // Pop first event from buffer
        Ok(buffer.remove(0))
    }
}

// Background task (spawned in connect())
let recv_task = tokio::spawn(async move {
    info!("🔄 [RECV_TASK] Background receive task started");
    let mut recv = recv_shared.lock().await;
    let mut read_buf = vec![0u8; 8192];

    loop {
        // Blocking is OK here - in background task
        match recv.read(&mut read_buf).await {
            Ok(Some(n)) => {
                if n > 0 {
                    match MessageCodec::decode(&read_buf[..n]) {
                        Ok(NetworkMessage::Event(event)) => {
                            // Push to buffer - receive_event() polls from here
                            let mut buffer = event_buffer.lock().await;
                            buffer.push(event);
                        }
                        // ...
                    }
                }
            }
            // ...
        }
    }
});
```

### Deadlock Analysis

#### Call Stack During Hang

```
[Dart Isolate - Main Thread]
  ├─ Timer.periodic(100ms) fires
  ├─ bridge.receiveEvent() called
  │   └─ FFI call to Rust
  │       └─ receive_terminal_command()
  │           └─ client.receive_event()
  │               └─ 🔴 recv.read().await [BLOCKS WAITING FOR DATA]
  │                   [Dart isolate FROZEN - no async yields]
  │
  └─ [User types command + hits Send]
      └─ _sendInput()
          └─ bridge.sendCommand()
              └─ 🔴 NEVER RUNS - isolate still blocked in receiveEvent()
```

#### Why It Never Completes

1. **Timer calls `receiveEvent()` every 100ms**
2. `receiveEvent()` blocks on `recv.read()` waiting for server data
3. Dart isolate frozen - can't process any other async operations
4. `sendCommand()` submitted to same isolate queue
5. **Deadlock**: `sendCommand()` waits for isolate, isolate waits for QUIC data

### api.rs Changes (Also Uncommitted)

```diff
- static QUIC_CLIENT: OnceCell<Arc<Mutex<QuicClient>>> = OnceCell::new();
+ static QUIC_CLIENT: OnceCell<tokio::sync::RwLock<Option<Arc<Mutex<QuicClient>>>>> = OnceCell::new();

- let client_arc = QUIC_CLIENT.get()
-     .ok_or_else(|| "Not connected. Call connect_to_host first.".to_string())?;
+ let client_arc = get_client().await?;
```

**Impact:** Refactors from `OnceCell<Arc<Mutex<QuicClient>>>` to `OnceCell<RwLock<Option<>>>` for reconnect support.

---

## Evidence

### File Timestamps

```bash
$ stat -f "%Sm" mobile/ios/Frameworks/libmobile_bridge.a
2026-01-21 15:16:24  # 🔴 OLD - built before Phase 09 fix
```

### Git Status

```bash
$ git status --short crates/mobile_bridge/
 M crates/mobile_bridge/src/api.rs         # 🔴 UNCOMMITTED
 M crates/mobile_bridge/src/quic_client.rs # 🔴 UNCOMMITTED
```

### Git Diff Summary

```bash
$ git diff HEAD --stat -- crates/mobile_bridge/
 crates/mobile_bridge/src/api.rs         | 135 +++++++++++++++++++----------
 crates/mobile_bridge/src/quic_client.rs | 147 +++++++++++++++++++++-----------
 2 files changed, 184 insertions(+), 98 deletions(-)
```

### Log Evidence

**Expected logs:**
```
flutter: 🟢 [Terminal] Sending command: "ping 8.8.8.8"
flutter: 🔵 [BridgeWrapper] sendCommand called: "ping 8.8.8.8"
[Rust] 🔵 [FRB] Sending command: 'ping 8.8.8.8'
[Rust] 🔵 [QUIC_CLIENT] send_command called: 'ping 8.8.8.8'
[Rust] 📤 [QUIC_CLIENT] Sending 45 bytes
[Rust] ✅ [QUIC_CLIENT] Command sent successfully
[Rust] ✅ [FRB] Command sent successfully
flutter: ✅ [Terminal] Command sent successfully
flutter: ✅ [BridgeWrapper] sendCommand completed
```

**Actual logs:**
```
flutter: 🟢 [Terminal] Sending command: "ping 8.8.8.8"
flutter: 🔵 [BridgeWrapper] sendCommand called: "ping 8.8.8.8"
[🔴 HANGS FOREVER - NO MORE LOGS]
```

---

## Root Cause

**Primary:** iOS static library (`libmobile_bridge.a`) built with blocking `receive_event()` code. When Flutter's event loop timer calls `receiveEvent()`, it blocks on QUIC stream read, freezing the Dart isolate. `sendCommand()` can't complete because isolate is blocked.

**Secondary:**
1. Phase 09 background task fix implemented but **not committed**
2. Static library **not rebuilt** after code changes
3. Outdated library deployed to iOS device

---

## Recommended Actions

### Immediate Fix

1. **Commit the Phase 09 changes:**
   ```bash
   cd /Users/khoa2807/development/2026/Comacode
   git add crates/mobile_bridge/src/quic_client.rs
   git add crates/mobile_bridge/src/api.rs
   git commit -m "fix(mobile-bridge): implement Phase 09 background receive task pattern

   - Move receive operations to background Tokio task
   - Add Arc<Mutex<Vec<TerminalEvent>>> event buffer
   - Make receive_event() non-blocking (polls from buffer)
   - Fixes Dart isolate freeze on iOS"
   ```

2. **Rebuild iOS static library:**
   ```bash
   cargo build --release --target aarch64-apple-ios
   lipo -create target/aarch64-apple-ios/release/libmobile_bridge.a \
         -output mobile/ios/Frameworks/libmobile_bridge.a
   ```

3. **Clean rebuild iOS app:**
   ```bash
   cd mobile/ios
   rm -rf Pods Podfile.lock .symlinks
   pod install
   cd ..
   flutter clean
   flutter pub get
   flutter build ios
   ```

4. **Deploy to device:**
   ```bash
   flutter install
   ```

### Verification

After deployment, check logs for:
```
[Rust] 🔄 [RECV_TASK] Background receive task started
[Rust] 📥 [RECV_TASK] Received event, buffering
flutter: ✅ [Terminal] Command sent successfully
flutter: ✅ [BridgeWrapper] sendCommand completed
```

### Long-term Improvements

1. **Add build timestamp to library:**
   ```rust
   const BUILD_TIMESTAMP: &str = env!("VERGEN_BUILD_TIMESTAMP");
   ```

2. **Add version check API:**
   ```rust
   #[frb]
   pub fn get_library_version() -> String {
       format!("{} {}", env!("CARGO_PKG_VERSION"), env!("VERGEN_BUILD_TIMESTAMP"))
   }
   ```

3. **Automate iOS library rebuild in CI:**
   - Detect Rust code changes
   - Auto-rebuild `libmobile_bridge.a`
   - Fail build if library outdated

4. **Add startup version check:**
   ```dart
   // In main.dart
   final version = await RustLib.instance.api.getLibraryVersion();
   debugPrint('Rust library version: $version');
   ```

---

## Unresolved Questions

1. **Why does background receive task fix the block?**
   - Answer: Moves blocking QUIC read to background Tokio task, `receive_event()` polls from non-blocking buffer

2. **Is there a deadlock in the old code?**
   - Not a deadlock per se, but a **block**: `receiveEvent()` blocks isolate, preventing `sendCommand()` from running

3. **Can we add timeout to sendCommand?**
   - Yes, but won't help - real issue is isolate frozen in `receiveEvent()`

4. **Why does this only affect iOS?**
   - Likely timing difference - Android may have different event loop behavior or QUIC read timing

5. **Is the uncommitted code ready for production?**
   - Need review - Phase 09 pattern is sound but untested

---

## Files Requiring Changes

### Code (Already Changed - Just Commit)
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs`
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/api.rs`

### Build Artifacts (Need Rebuild)
- `/Users/khoa2807/development/2026/Comacode/mobile/ios/Frameworks/libmobile_bridge.a`

### Verification (After Deploy)
- Check iOS logs for `[RECV_TASK]` messages
- Verify `sendCommand()` completes without hang
- Test multiple rapid commands

---

## References

- **Phase 09 Design:** Non-blocking event polling with background task
- **Related Issue:** debugger-260120-1640-terminal-command-not-received.md
- **Code Pattern:** Background Tokio task + Arc<Mutex<Vec>> buffer
- **Flutter FFI:** Dart isolate blocking on Rust async calls

---

**Next Steps:**
1. ✅ Code changes identified
2. ⏳ Commit changes
3. ⏳ Rebuild iOS static library
4. ⏳ Clean build iOS app
5. ⏳ Deploy and test
6. ⏳ Verify logs for non-blocking behavior

**Estimated Time to Fix:** 30 minutes (build + deploy + test)
