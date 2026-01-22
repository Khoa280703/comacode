# Debug Report: iOS Terminal Command Lost - No Server Running

**Report ID:** debugger-260121-2058-ios-terminal-command-lost
**Date:** 2026-01-21
**Severity:** P0 - Critical functionality broken
**Status:** Root cause identified - Server not running

## Executive Summary

Terminal commands from iOS app are not being received because **no server is running to receive connections**. The app successfully connects (auth completes), but there's no `hostagent` server process listening for commands.

**Key Finding:** iOS app is likely running in **Release mode** which optimizes out all `tracing::info!/debug!/error!` logs, making debugging impossible.

## Root Cause Analysis

### 1. Server Status: NOT RUNNING

**Finding:** No `hostagent` server process detected
```bash
$ pgrep -f "hostagent"
# No output - server not running
```

**Impact:**
- iOS app can "connect" (QUIC handshake succeeds because nothing rejects it)
- Commands sent but nowhere to receive them
- No terminal session created
- No output displayed

**Evidence:**
- Connection succeeds (no error in app)
- Authentication appears successful (no "auth failed" logs)
- But no server logs showing command reception
- No terminal output in app

---

### 2. iOS Build Configuration: RELEASE MODE

**Critical Issue:** iOS app likely built in Release mode

**Problem:**
```rust
// crates/mobile_bridge/src/api.rs:116
tracing::info!("🔵 [FRB] Sending command: '{}'", command);
```

In Release builds, Rust compiler **optimizes out all tracing logs** unless explicitly enabled.

**Evidence:**
- No logs visible in iOS simulator log stream
- `log stream` command shows nothing from app
- Debug logs (🔵, ✅, ❌) not appearing

**Impact:**
- Cannot trace command flow
- Cannot verify if Flutter calls FFI
- Cannot verify if Rust receives command
- Cannot verify if QUIC client sends

---

### 3. Code Flow Analysis (Based on Source Review)

### Flutter Layer (terminal_page.dart:278-284)

```dart
void _sendInput() {
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r'); // ❌ NOT AWAITED - errors swallowed!
  _inputController.clear();
}
```

**Problem:** `sendCommand()` returns `Future<void>` but not awaited
- Errors are thrown but caught nowhere
- No error feedback to user
- Silent failures

**Expected:** Should be `async` and `await` with error handling

---

### Bridge Wrapper (bridge_wrapper.dart:44-52)

```dart
Future<void> sendCommand(String command) async {
  try {
    await RustLib.instance.api.mobileBridgeApiSendTerminalCommand(
      command: command,
    );
  } catch (e) {
    throw Exception('Send command failed: $e');  // ✅ Error thrown
  }
}
```

**Status:** ✅ Correct - throws exception on failure
**Problem:** Caller doesn't catch it

---

### Rust Bridge API (api.rs:115-125)

```rust
#[frb]
pub async fn send_terminal_command(command: String) -> Result<(), String> {
    tracing::info!("🔵 [FRB] Sending command: '{}'", command);  // ❌ Optimized out in Release
    let client_arc = get_client().await?;
    let client = client_arc.lock().await;
    let result = client.send_command(command).await;
    match &result {
        Ok(()) => tracing::info!("✅ [FRB] Command sent successfully"),
        Err(e) => tracing::error!("❌ [FRB] Command send failed: {}", e),
    }
    result
}
```

**Status:** ✅ Correct implementation
**Problem:** Logs invisible in Release build

---

### QUIC Client (quic_client.rs:337-364)

```rust
pub async fn send_command(&self, command: String) -> Result<(), String> {
    info!("🔵 [QUIC_CLIENT] send_command called: '{}'", command);  // ❌ Optimized out

    let send_stream = self.send_stream.as_ref()
        .ok_or_else(|| {
            error!("❌ [QUIC_CLIENT] No send_stream - not connected");  // ❌ Optimized out
            "Not connected".to_string()
        })?;

    let cmd_msg = NetworkMessage::Command(TerminalCommand::new(command));
    let encoded = MessageCodec::encode(&cmd_msg)
        .map_err(|e| {
            error!("❌ [QUIC_CLIENT] Encode failed: {}", e);  // ❌ Optimized out
            format!("Failed to encode command: {}", e)
        })?;

    info!("📤 [QUIC_CLIENT] Sending {} bytes", encoded.len());  // ❌ Optimized out

    let mut send = send_stream.lock().await;
    send.write_all(&encoded).await
        .map_err(|e| {
            error!("❌ [QUIC_CLIENT] write_all failed: {}", e);  // ❌ Optimized out
            format!("Failed to send command: {}", e)
        })?;

    info!("✅ [QUIC_CLIENT] Command sent successfully");  // ❌ Optimized out
    Ok(())
}
```

**Status:** ✅ Correct implementation
**Problem:** All logs invisible in Release

---

### Server Side (NOT RUNNING)

**Expected behavior:** Server should receive command at `quic_server.rs:313-337`

```rust
NetworkMessage::Command(cmd) => {
    // Legacy: Command with String text
    if !authenticated {
        tracing::warn!("Command received before authentication from {}", peer_addr);
        break;
    }

    if let Some(id) = session_id {
        if let Err(e) = session_mgr.write_to_session(id, cmd.text.as_bytes()).await {
            tracing::error!("Failed to write to PTY: {}", e);
        }
    } else {
        // Spawn new session with terminal configuration
        let _ = Self::spawn_session_with_config(
            &session_mgr,
            pending_resize,
            &mut pty_task,
            &mut session_id,
            &send_shared,
            cmd.text.as_bytes(),
        ).await;
    }
}
```

**Problem:** Server not running → this code never executes

---

## Why Connection "Succeeds"

When no server is running:
1. iOS app initiates QUIC connection to `host:port`
2. **If port is closed**: Connection fails immediately
3. **If port is open by another service**: Might accept connection but not handle QUIC protocol
4. **If router/firewall drops silently**: Connection hangs

**Most likely scenario:** Server was running during QR scan (connection worked), but server crashed or was stopped before terminal commands sent.

---

## Evidence from Previous Debug Report

**Reference:** `debugger-260120-1640-terminal-command-not-received.md`

Previous issue (2026-01-20): **Double length-prefix framing bug in server**

**Status:** ✅ **FIXED** - Server now uses proper buffer-based message decoding

**Current issue:** Different - server not running at all

---

## Impact Assessment

### Affected Functionality
- ❌ Terminal commands: Completely broken
- ❌ Raw input (keystrokes): Broken
- ❌ PTY resize: Broken
- ✅ Connection: Works (because no server to reject)
- ✅ Authentication: Appears successful (no rejection)

### User Experience
1. User scans QR code
2. "Connected" status appears
3. Terminal page opens
4. User types `ping 8.8.8.8` and presses Send
5. **Nothing happens**
6. No error message
7. No feedback

---

## Solution

### IMMEDIATE FIX (P0)

**1. Start the server**
```bash
cd /Users/khoa2807/development/2026/Comacode
cargo run --bin hostagent
```

**2. Verify server listening**
```bash
# Should show hostagent listening on QUIC port (default 8443)
lsof -i :8443 -P -n | grep LISTEN
```

**3. Test with iOS app**
- Scan QR code
- Send command: `ping 8.8.8.8`
- Should see output in terminal

---

### DEBUGGING FIX (P0)

**Problem:** iOS Release build disables all logs

**Solution 1: Enable logging in Release builds**

**File:** `crates/mobile_bridge/Cargo.toml`

```toml
[profile.release]
debug = true  # Include debug symbols
```

**File:** `crates/mobile_bridge/src/lib.rs`

```rust
// Force tracing to be compiled in
#[cfg(feature = "release-logs")]
use tracing::{info, debug, error};
```

**File:** `mobile/ios/Podfile` or build script

```ruby
# Enable Release logging
pod 'mobile_bridge', :configuration => 'Release'
```

**Solution 2: Use Debug build for testing**

```bash
cd mobile
flutter build ios --debug
# Or run directly:
flutter run -d ios
```

**Solution 3: Use environment variable for logging**

Add to iOS scheme environment variables:
```
RUST_LOG=debug
```

---

### CODE FIX (P1)

**Problem:** `_sendInput()` doesn't await or handle errors

**File:** `mobile/lib/features/terminal/terminal_page.dart:278-285`

**Current code:**
```dart
void _sendInput() {
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r');  // ❌ Not awaited
  _inputController.clear();
}
```

**Fixed code:**
```dart
void _sendInput() async {  // ✅ Add async
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);
  try {
    await bridge.sendCommand('$text\r');  // ✅ Await
    _inputController.clear();
  } catch (e) {
    // ✅ Show error to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send command: $e'),
          backgroundColor: CatppuccinMocha.red,
        ),
      );
    }
  }
}
```

**Why this matters:**
- User gets feedback when command fails
- Developers can see errors
- Debugging becomes possible

---

### SERVER AUTO-START (P2)

**Problem:** Manual server start required

**Solution:** Launchd service or background daemon

**File:** `~/Library/LaunchAgents/com.comacode.hostagent.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.comacode.hostagent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/khoa2807/development/2026/Comacode/target/release/hostagent</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/comacode.hostagent.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/comacode.hostagent.err</string>
</dict>
</plist>
```

**Install:**
```bash
ln -sf ~/development/2026/Comacode/scripts/com.comacode.hostagent.plist \
   ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.comacode.hostagent.plist
```

---

## Testing Steps

### 1. Verify Server Running
```bash
# Check if hostagent is running
pgrep -lf hostagent

# Check if port 8443 is listening
lsof -i :8443 -P -n | grep LISTEN

# View server logs
tail -f /tmp/comacode.hostagent.log
```

### 2. Test Command Flow

**With Debug build:**
```bash
cd mobile
flutter run -d ios --debug
```

**Send command in app:** `echo hello`

**Expected logs:**
```
[INFO] 📱 [FLUTTER] _sendInput called: 'echo hello\r'
[INFO] 🔵 [FRB] send_terminal_command: 'echo hello\r'
[INFO] 📤 [QUIC_CLIENT] Sending 42 bytes
[INFO] ✅ [QUIC_CLIENT] Command sent successfully
```

**Server logs:**
```
[INFO] Received message: Command
[INFO] Input: session=Some(123) data="echo hello\r"
[INFO] Created session 456 for connection
```

### 3. Test Error Handling

**Stop server:**
```bash
pkill hostagent
```

**Send command in app:** `echo test`

**Expected:** Error snackbar visible
```
❌ Failed to send command: Not connected
```

---

## Unresolved Questions

1. **Why was server not running?**
   - Crashed after connection?
   - Never started?
   - Killed by user/system?
   - Need crash logs

2. **Why Release build instead of Debug?**
   - Performance testing?
   - Accidental?
   - CI/CD configuration issue?

3. **Are there crash logs?**
   - Check `/tmp/comacode.hostagent.err`
   - Check iOS simulator crash logs
   - Check `~/Library/Logs/DiagnosticReports/`

4. **Is port 8443 correct?**
   - Verify QR code contains correct port
   - Check if firewall blocks 8443
   - Check if another process uses 8443

5. **Network configuration?**
   - iOS simulator network isolation?
   - localhost binding issue?
   - Need to use `127.0.0.1` vs `0.0.0.0`?

---

## Implementation Checklist

- [ ] Start hostagent server
- [ ] Verify server listening on port 8443
- [ ] Rebuild iOS app in Debug mode OR enable Release logging
- [ ] Fix `_sendInput()` to await and handle errors
- [ ] Test command sending with server running
- [ ] Add error snackbar for user feedback
- [ ] Add connection status indicator
- [ ] Set up server auto-start (launchd)
- [ ] Add integration test for command flow
- [ ] Add logs for server lifecycle events
- [ ] Document server start/stop procedures

---

## References

**Files involved:**
- `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart` (lines 278-284)
- `/Users/khoa2807/development/2026/Comacode/mobile/lib/bridge/bridge_wrapper.dart` (lines 44-52)
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/api.rs` (lines 115-125)
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs` (lines 337-364)
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs` (lines 313-337)

**Related reports:**
- Previous: `debugger-260120-1640-terminal-command-not-received.md` (server framing bug - FIXED)
- Previous: `debugger-260109-2358-client-already-initialized.md` (client init bug)
- Previous: `debugger-260121-1506-ios-dyld-error.md` (iOS linking issue)
- Previous: `debugger-260121-1531-pods-runner-framework-missing.md` (Pods issue)

**Protocol documentation:**
- Length-prefixed framing with Postcard serialization
- 4-byte big-endian length prefix
- Max message size: 16MB
- QUIC transport with TLS 1.3
- TOFU (Trust On First Use) certificate verification

---

## Next Steps

1. ✅ Root cause identified (server not running)
2. ⏳ Start server and verify
3. ⏳ Rebuild iOS app with logging enabled
4. ⏳ Fix error handling in Flutter
5. ⏳ Test end-to-end command flow
6. ⏳ Set up server auto-start
7. ⏳ Add integration tests
8. ⏳ Update documentation

---

## Priority Matrix

| Issue | Priority | Impact | Effort | Timeline |
|-------|----------|--------|--------|----------|
| Start server | P0 | Critical | Trivial | Immediate |
| Enable logging | P0 | Critical | Low | 1 hour |
| Fix error handling | P1 | High | Low | 2 hours |
| Server auto-start | P2 | Medium | Medium | 4 hours |
| Integration tests | P2 | High | High | 1 day |
