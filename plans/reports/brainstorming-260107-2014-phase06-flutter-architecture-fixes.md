# Brainstorming Report: Phase 06 Flutter UI - Architecture Fixes

**Date**: 2026-01-07
**Type**: Architecture Review
**Status**: ✅ Complete - Plan Updated

---

## Problem Statement

Plan Phase 06 gốc có 4 vấn đề kiến trúc cần fix trước khi implement:
1. BridgeWrapper dùng static methods + singleton (anti-pattern với Riverpod)
2. Terminal resize handling chưa implement
3. Clipboard integration chưa implement
4. FFI write buffering cần review

---

## Decisions Made

### 1. BridgeWrapper Architecture ✅ CRITICAL FIX

**Problem**: Static methods không thể test/mock, conflict với Riverpod

**Solution**: Refactor sang Riverpod provider

```dart
// ❌ OLD (Anti-pattern)
class BridgeWrapper {
  static final BridgeWrapper _instance = BridgeWrapper._();
  static Future<void> connect(...) async {}
}

// ✅ NEW (Riverpod)
@riverpod
BridgeWrapper bridgeWrapper(BridgeWrapperRef ref) {
  return BridgeWrapper();
}

class BridgeWrapper {
  Future<void> connect(...) async {}  // Instance method
}

// Usage:
final bridge = ref.read(bridgeWrapperProvider);
await bridge.connect(...);
```

**Benefits**:
- Dễ test (mock BridgeWrapper)
- Dùng với Riverpod ConsumerWidget
- Type-safe với code generation

---

### 2. PTY Resize Handling ✅ REQUIRED

**Problem**: Khi rotate màn hình, layout bị vỡ nếu không resize PTY

**Solution**: Thêm `resizePty()` vào BridgeWrapper

```dart
// Dart side
class BridgeWrapper {
  Future<void> resizePty({required int rows, required int cols}) async {
    await api.resizePty(rows: rows, cols: cols);
  }
}

// Rust side (crates/mobile_bridge/src/api.rs)
#[frb(sync)]
pub fn resize_pty(rows: u16, cols: u16) -> Result<(), String> {
    // Send NetworkMessage::Resize via QUIC
}
```

```dart
// Terminal backend
@override
void resize(int width, int height, int pixelWidth, int pixelHeight) {
  bridge.resizePty(rows: height, cols: width);
}
```

---

### 3. Clipboard Integration ✅ NICE_TO_HAVE

**Problem**: User không thể copy IP/password từ terminal

**Solution**: Hook vào xterm.dart `onSelectionChanged`

```dart
_terminal.onSelectionChanged = (selectedText) {
  if (selectedText != null && selectedText.isNotEmpty) {
    Clipboard.setData(ClipboardData(text: selectedText));
  }
};
```

---

### 4. Write Buffering ⚠️ DEFERRED

**Analysis**:
- xterm.dart gọi write() theo từng keystroke
- FFI overhead: ~50-100µs per call
- Network latency (QUIC): >> FFI overhead

**Decision**: Skip buffering cho MVP, chỉ add nếu user báo lag

---

## Files Updated

| File | Changes |
|------|---------|
| `phase-06-flutter-ui.md` | BridgeWrapper → Riverpod provider |
| `phase-06-flutter-ui.md` | Add resizePty() method |
| `phase-06-flutter-ui.md` | Add onSelectionChanged → clipboard |
| `phase-06-flutter-ui.md` | Update all usages (ConnectionState, TerminalWidget, QRScanner) |
| `phase-06-flutter-ui.md` | Update tasks + success criteria |
| `phase-06-flutter-ui.md` | Update risk assessment |

---

## Action Items

### Before Implement
1. ✅ Review plan - Done
2. ⏳ Add `resize_pty()` to `crates/mobile_bridge/src/api.rs`
3. ⏳ Run `flutter pub run build_runner build` after FRB update

### During Implementation
1. ⏳ Use `ref.read(bridgeWrapperProvider)` everywhere
2. ⏳ Test resize on physical device (rotation)
3. ⏳ Test clipboard (select → copy → paste)

---

## Risk Reduction

| Risk | Before | After |
|------|--------|-------|
| FFI testing | Hard (static) | Easy (instance) |
| Screen rotation | Broken | ✅ Fixed |
| Copy/paste | Missing | ✅ Implemented |
| State management | Fragile | ✅ Riverpod native |

---

## Next Steps

1. Implement Phase 06 với updated plan
2. Test resize on real device (critical)
3. Test clipboard workflow
4. Proceed to Phase 07: Discovery & Auth

---

*Report generated: 2026-01-07*
*Brainstorming complete - Plan updated*
