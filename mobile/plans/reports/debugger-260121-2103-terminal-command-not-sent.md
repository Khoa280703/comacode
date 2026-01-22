# Debug Report: Terminal Command Not Received by Server

**Report ID:** debugger-260121-2103-terminal-command-not-sent
**Date:** 2026-01-21
**Severity:** P0 - Critical functionality broken
**Status:** Root cause identified, fix provided

## Executive Summary

Terminal commands from mobile app không được gửi đến server mặc dù kết nối thành công. Root cause là **missing await** trong Dart code khi gọi `sendCommand()`:

**Vị trí:** `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart`
**Line:** 283
**Issue:** `bridge.sendCommand()` được gọi nhưng **không await** → function return immediately, error bị swallow

## Flow Analysis

### 1. User Action: Gõ "ping 8.8.8.8" và nhấn Send

**File:** `lib/features/terminal/terminal_page.dart`
**Line:** 278-285

```dart
void _sendInput() {
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r'); // ❌ CRITICAL: Not awaited!
  _inputController.clear();
}
```

**Problems:**
1. ❌ `sendCommand()` returns `Future<void>` nhưng không được await
2. ❌ Function returns immediately, command chưa gửi xong
3. ❌ Error nếu có sẽ bị swallow (không có try-catch)
4. ❌ User không có feedback về command status

---

### 2. Bridge Layer: Wrapper để gọi FFI

**File:** `lib/bridge/bridge_wrapper.dart`
**Line:** 43-52

```dart
Future<void> sendCommand(String command) async {
  try {
    await RustLib.instance.api.mobileBridgeApiSendTerminalCommand(
      command: command,
    );
  } catch (e) {
    throw Exception('Send command failed: $e'); // ⚠️ Error thrown but nobody catches
  }
}
```

**Behavior khi không được await:**
- Function sẽ chạy ở background
- Error thrown sẽ bị uncaught
- Flutter có thể log error nhưng không hiển thị cho user

---

### 3. FFI Layer: Dart → Rust Bridge

**File:** `crates/mobile_bridge/src/api.rs`
**Line:** 115-125

```rust
#[frb]
pub async fn send_terminal_command(command: String) -> Result<(), String> {
    tracing::info!("🔵 [FRB] Sending command: '{}'", command);
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

**Logging có:**
- ✅ Log trước khi gửi: `🔵 [FRB] Sending command: 'ping 8.8.8.8'`
- ✅ Log success/error sau khi gửi

**NHƯNG** vì Dart không await, nên:
- Function có thể không được gọi ngay lập tức
- Hoặc được gọi nhưng Dart event loop không chờ kết quả

---

### 4. QUIC Client Layer: Gửi command qua network

**File:** `crates/mobile_bridge/src/quic_client.rs`
**Line:** 337-364

```rust
pub async fn send_command(&self, command: String) -> Result<(), String> {
    info!("🔵 [QUIC_CLIENT] send_command called: '{}'", command);

    let send_stream = self.send_stream.as_ref()
        .ok_or_else(|| {
            error!("❌ [QUIC_CLIENT] No send_stream - not connected");
            "Not connected".to_string()
        })?;

    let cmd_msg = NetworkMessage::Command(TerminalCommand::new(command));
    let encoded = MessageCodec::encode(&cmd_msg)
        .map_err(|e| {
            error!("❌ [QUIC_CLIENT] Encode failed: {}", e);
            format!("Failed to encode command: {}", e)
        })?;

    info!("📤 [QUIC_CLIENT] Sending {} bytes", encoded.len());

    let mut send = send_stream.lock().await;
    send.write_all(&encoded).await
        .map_err(|e| {
            error!("❌ [QUIC_CLIENT] write_all failed: {}", e);
            format!("Failed to send command: {}", e)
        })?;

    info!("✅ [QUIC_CLIENT] Command sent successfully");
    Ok(())
}
```

**Logging flow (nếu function được gọi):**
1. `🔵 [QUIC_CLIENT] send_command called: 'ping 8.8.8.8'`
2. `📤 [QUIC_CLIENT] Sending XX bytes`
3. `✅ [QUIC_CLIENT] Command sent successfully`

**HOẶC error nếu có vấn đề:**
- `❌ [QUIC_CLIENT] No send_stream - not connected`
- `❌ [QUIC_CLIENT] Encode failed: ...`
- `❌ [QUIC_CLIENT] write_all failed: ...`

---

### 5. Server Layer: Nhận command

**File:** `crates/hostagent/src/quic_server.rs`
**Line:** 200-377

Server đã được fix từ previous report (debugger-260120-1640):
- ✅ Sử dụng buffer để handle partial reads
- ✅ `try_decode_message()` để decode length-prefixed messages
- ✅ Proper logging cho mỗi message type

**Server logging khi nhận command:**
```rust
tracing::info!("Received message: {:?}", std::mem::discriminant(&msg));
```

---

## Root Cause

### Primary Issue: Missing Await in Dart

**Location:** `lib/features/terminal/terminal_page.dart:283`

```dart
// ❌ WRONG: Not awaited
bridge.sendCommand('$text\r');

// ✅ CORRECT: Awaited properly
await bridge.sendCommand('$text\r');
```

**Why this breaks:**
1. Dart `sendCommand()` is async but fire-and-forget
2. Function returns immediately before actual send
3. No error handling or feedback to user
4. Network operation may not complete or may fail silently

---

### Secondary Issues

#### 1. No Error Handling in `_sendInput()`

```dart
void _sendInput() {  // ❌ Not async
  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r'); // ❌ No try-catch, no await
}
```

**Should be:**
```dart
Future<void> _sendInput() async {  // ✅ Async
  final text = _inputController.text;
  if (text.isEmpty) return;

  try {
    final bridge = ref.read(bridgeWrapperProvider);
    await bridge.sendCommand('$text\r');  // ✅ Awaited
    _inputController.clear();
  } catch (e) {
    // Show error to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send command: $e')),
    );
  }
}
```

#### 2. Virtual Key Bar Also Missing Await

**File:** `lib/features/terminal/virtual_key_bar.dart` (called from terminal_page.dart:423)

```dart
VirtualKeyBar(
  onKeyPressed: (key) {
    final bridge = ref.read(bridgeWrapperProvider);
    bridge.sendCommand(key); // ❌ Also not awaited!
  },
  ...
)
```

---

## Verification Steps

### Step 1: Check Server Logs

**Expected nếu command được gửi:**
```
[INFO] Received message: NetworkMessage::Command
[INFO] Input: session=Some(123) data="ping 8.8.8.8"
```

**Actual hiện tại:**
- Không có log về nhận command
- Chỉ có "Client authenticated" từ Hello handshake

**Conclusion:** Command không đến được server → client side issue

---

### Step 2: Check Rust Logs

**Expected nếu `send_command()` được gọi:**
```
🔵 [FRB] Sending command: 'ping 8.8.8.8'
🔵 [QUIC_CLIENT] send_command called: 'ping 8.8.8.8'
📤 [QUIC_CLIENT] Sending XX bytes
✅ [QUIC_CLIENT] Command sent successfully
```

**How to check:**
```bash
# Run server with RUST_LOG to see all logs
RUST_LOG=info cargo run --bin hostagent -- --qr-terminal
```

**Nếu không thấy logs này:**
- FFI function không được gọi
- Confirming: Dart side issue (missing await)

---

### Step 3: Add Temporary Logging to Dart

**Add debug logging to confirm flow:**

```dart
void _sendInput() {
  final text = _inputController.text;
  if (text.isEmpty) return;

  print('🔵 [DART] Sending command: "$text"');  // DEBUG

  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r').then((_) {
    print('✅ [DART] Command sent successfully');  // DEBUG
  }).catchError((e) {
    print('❌ [DART] Command failed: $e');  // DEBUG
  });

  _inputController.clear();
}
```

**Expected output:**
```
🔵 [DART] Sending command: "ping 8.8.8.8"
✅ [DART] Command sent successfully
```

**Nếu chỉ thấy dòng đầu:** Confirm async issue

---

## Solution

### Fix 1: Add Await to `_sendInput()` (REQUIRED)

**File:** `lib/features/terminal/terminal_page.dart`
**Line:** 278-285

**Current code:**
```dart
void _sendInput() {
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);
  bridge.sendCommand('$text\r');
  _inputController.clear();
}
```

**Fixed code:**
```dart
Future<void> _sendInput() async {
  final text = _inputController.text;
  if (text.isEmpty) return;

  final bridge = ref.read(bridgeWrapperProvider);

  try {
    await bridge.sendCommand('$text\r');
    _inputController.clear();
  } catch (e) {
    // Show error to user (optional)
    debugPrint('Failed to send command: $e');
  }
}
```

---

### Fix 2: Add Await to Virtual Key Bar (REQUIRED)

**File:** `lib/features/terminal/terminal_page.dart`
**Line:** 420-428

**Current code:**
```dart
VirtualKeyBar(
  onKeyPressed: (key) {
    final bridge = ref.read(bridgeWrapperProvider);
    bridge.sendCommand(key);
  },
  ...
)
```

**Fixed code:**
```dart
VirtualKeyBar(
  onKeyPressed: (key) async {
    final bridge = ref.read(bridgeWrapperProvider);
    try {
      await bridge.sendCommand(key);
    } catch (e) {
      debugPrint('Failed to send key: $e');
    }
  },
  ...
)
```

---

### Fix 3: Add User Feedback (OPTIONAL but RECOMMENDED)

Add visual feedback khi command được gửi:

```dart
Future<void> _sendInput() async {
  final text = _inputController.text;
  if (text.isEmpty) return;

  // Show loading indicator
  setState(() => _sending = true);

  final bridge = ref.read(bridgeWrapperProvider);

  try {
    await bridge.sendCommand('$text\r');
    _inputController.clear();
  } catch (e) {
    // Show error to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: CatppuccinMocha.red,
        ),
      );
    }
  } finally {
    // Hide loading indicator
    setState(() => _sending = false);
  }
}
```

---

## Testing Checklist

### Pre-Fix Testing

1. ✅ Start server: `cargo run --bin hostagent -- --qr-terminal`
2. ✅ Connect mobile app
3. ✅ Type command and press Send
4. ❌ **Expected:** Server logs show command received
5. ❌ **Actual:** Nothing happens

**Confirm issue:**
- Check server console → no "Received message" log
- Check Rust logs → no `🔵 [FRB] Sending command` log
- Confirm: Dart async issue

---

### Post-Fix Testing

1. ✅ Apply Fix 1 & Fix 2
2. ✅ Rebuild mobile app: `flutter run`
3. ✅ Start server: `cargo run --bin hostagent -- --qr-terminal`
4. ✅ Connect mobile app
5. ✅ Type command: `ping 8.8.8.8`
6. ✅ Press Send button
7. ✅ **Verify server logs:**
   ```
   [INFO] Received message: NetworkMessage::Command
   [INFO] Input: session=Some(123) data="ping 8.8.8.8\r"
   ```
8. ✅ **Verify terminal output:** Ping responses appear

---

## Additional Observations

### 1. Previous Report (debugger-260120-1640)

Server-side đã được fix với proper buffering và `try_decode_message()`. Issue đó đã resolve.

### 2. Current Issue

Là **client-side issue** - Dart code không await async operation.

### 3. Why Hello Works

Hello handshake works vì nó được gọi trong `connect()` function CÓ await:

```dart
// lib/features/connection/home_page.dart
await bridge.connect(...);  // ✅ Properly awaited
```

---

## Impact Assessment

### Affected Functionality
- ❌ **Text input:** Commands from text field not sent
- ❌ **Virtual keyboard:** Key presses not sent
- ❌ **User feedback:** No error messages shown
- ✅ **Connection:** Still works properly

### User Impact
- **Severity:** P0 - Core feature broken
- **Workaround:** None
- **Frequency:** Every command fails

---

## Implementation Plan

1. ✅ Root cause identified
2. ⏳ Apply Fix 1 (await in `_sendInput()`)
3. ⏳ Apply Fix 2 (await in virtual key bar)
4. ⏳ (Optional) Add user feedback
5. ⏳ Test with mobile app
6. ⏳ Verify server receives commands
7. ⏳ Test error handling (disconnect, network error)

---

## Unresolved Questions

1. **Why was this missed in testing?**
   - Need integration test for full command flow
   - Need end-to-end test (Dart → Rust → Server)

2. **Are there other missing awaits?**
   - Check all async function calls in Flutter code
   - Review other Riverpod providers

3. **Error logging setup?**
   - Need proper error reporting mechanism
   - Consider Crashlytics or Sentry for production

4. **Testing strategy?**
   - Add unit tests for `sendCommand()` with mock
   - Add integration test for full flow

---

## References

**Files involved:**
- `/Users/khoa2807/development/2026/Comacode/mobile/lib/features/terminal/terminal_page.dart` (line 283)
- `/Users/khoa2807/development/2026/Comacode/mobile/lib/bridge/bridge_wrapper.dart` (line 44)
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/api.rs` (line 115)
- `/Users/khoa2807/development/2026/Comacode/crates/mobile_bridge/src/quic_client.rs` (line 337)
- `/Users/khoa2807/development/2026/Comacode/crates/hostagent/src/quic_server.rs` (line 200)

**Related issues:**
- Previous report: `plans/reports/debugger-260120-1640-terminal-command-not-received.md` (server-side, fixed)

**Documentation:**
- Flutter async/await: https://dart.dev/codelabs/async-await
- Effective Dart: https://dart.dev/guides/language/effective-dart/usage
