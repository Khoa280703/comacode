---
title: "Planning Report: Phase 06 - Flutter UI"
date: 2026-01-07
type: planning
status: completed
---

# Planning Report: Phase 06 - Flutter UI

## Tóm Tắt

Đã tạo kế hoạch chi tiết cho **Phase 06: Flutter UI** của Comacode project - mobile app UI với QR scanner, terminal display, và kết nối QUIC backend.

## File Kế Hoạch

**Location:** `plans/260107-1929-phase06-flutter-ui/phase-06-flutter-ui.md`

## Phân Tích Chi Tiết

### 1. Tech Stack Đã Chọn

#### Terminal Widget: **xterm.dart** ✅
- **Lý do:** Native Flutter package, 60fps rendering, cross-platform
- **Tránh:** WebView-based xterm.js (phức tạp, performance issues)
- **Features:** Wide characters (CJK, emojis), dynamic theme, shortcut system
- **Source:** [pub.dev/xterm](https://pub.dev/packages/xterm)

#### State Management: **Riverpod** ✅
- **Lý do:** Type-safe, testable, scalable, compile-time safety
- **Ưu điểm:** Better than Provider (evolution), simpler than BLoC cho MVP
- **Integration:** FRB functions → Riverpod providers → UI
- **Trend 2025:** Increasingly popular cho new projects
- **Source:** Riverpod docs, Flutter community trends

#### QR Scanner: **mobile_scanner** ✅
- **Version:** ^5.0.0 (latest stable)
- **Features:** Camera controller lifecycle management, torch control
- **Permissions:** iOS (Info.plist) + Android (AndroidManifest.xml)
- **Source:** [pub.dev/mobile_scanner](https://pub.dev/packages/mobile_scanner)

### 2. Architecture Đề Xuất

```
mobile/
├── lib/
│   ├── features/
│   │   ├── qr_scanner/     # QR scanning logic
│   │   ├── terminal/       # xterm + virtual keyboard
│   │   ├── connection/     # Riverpod state management
│   │   └── settings/       # Saved hosts, app settings
│   ├── bridge/             # FRB wrapper
│   └── core/theme/         # Catppuccin Mocha
```

**Key Design Decisions:**
- **Riverpod generators** (@riverpod annotation) - Modern, type-safe
- **Feature-first structure** - Easy navigation, clear boundaries
- **Bridge wrapper** - Isolate FFI calls, add error handling
- **Catppuccin theme** - Consistency với codebase

### 3. Integration với Rust Backend

#### FFI Functions (Đã có từ Phase 04)
```rust
// crates/mobile_bridge/src/api.rs
pub async fn connect_to_host(...) → Result<(), String>
pub async fn send_command(...) → Result<(), String>
pub async fn receive_event() → Result<TerminalEvent, String>
pub async fn disconnect() → Result<(), String>
pub async fn is_connected() → bool
pub fn parse_qr_payload(...) → Result<QrPayload, String>
```

#### Dart Wrapper Pattern
```dart
class BridgeWrapper {
  static Future<void> connect(...)
  static Future<void> sendCommand(String command)
  static Future<TerminalEvent> receiveEvent()
  static Future<void> disconnect()
  static Future<bool> isConnected()
  static QrPayload parseQrPayload(String json)
}
```

**Rationale:**
- Clean separation giữa FFI layer và business logic
- Easier error handling
- Testable (mock wrapper cho unit tests)
- Single responsibility

### 4. Terminal Implementation Strategy

#### Backend Integration
```dart
class ComacodeTerminalBackend extends TerminalBackend {
  @override
  void write(String data) → bridge.sendCommand(data)

  @override
  void resize(int width, int height) → encode resize event

  @override
  void terminate() → bridge.disconnect()
}
```

#### Event Loop Pattern
```dart
// Infinite loop in StatefulWidget
while (mounted) {
  final event = await BridgeWrapper.receiveEvent();
  if (event.isOutput) {
    terminal.write(event.data);
  } else if (event.isError) {
    terminal.write('\x1b[31mError: ${event.message}\x1b[0m');
  }
}
```

**Critical:**
- Event loop runs in StatefulWidget (lifecycle bound to widget)
- Check `mounted` trước update UI (avoid memory leaks)
- Handle graceful errors (don't crash on bad events)

### 5. Virtual Keyboard Design

**Keys: ESC, CTRL, TAB, ALT, Arrows (↑↓←→)**

**Rationale:**
- Mobile keyboards lack ESC/CTRL - critical cho vim/nano
- TAB useful cho autocomplete
- Arrows cho navigation trong editors
- ALT cho meta-key combinations

**UX Consideration:**
- Toggle button để hide/show system keyboard
- Virtual keyboard covers 1/3 screen - user needs full view
- Haptic feedback (optional, Phase 06.1?)

### 6. Testing Strategy

#### Three Layers:
1. **Unit Tests** - Pure Dart logic (QrPayload, ConnectionModel)
2. **Integration Tests** - UI flow (navigation, state transitions)
3. **FFI Boundary Tests** - Bridge wrapper calls

**Critical:** Test FFI boundary early!
```dart
test('connect should throw on invalid host', () async {
  expect(() => BridgeWrapper.connect(host: 'invalid', ...),
         throwsException);
});
```

### 7. Effort Estimation

| Component | Estimate | Notes |
|-----------|----------|-------|
| Setup + Theme | 3h | Project create, deps, theme |
| QR Scanner | 4h | mobile_scanner integration |
| Connection | 2h | Riverpod provider + state |
| Terminal | 6h | xterm + backend + event loop |
| Settings | 2h | Saved hosts, preferences |
| Testing | 3h | Unit + integration + FFI |
| **Total** | **20h** | **~2.5 days** |

**Original estimate:** 16-24h (from roadmap)
**Revised:** 20h (dựa trên research, realistic)

### 8. Dependencies & Blockers

#### Completed:
- ✅ Rust QUIC client (Phase 04)
- ✅ FFI functions (api.rs)
- ✅ QR payload format (core/types/qr.rs)

#### Pending:
- ⏳ **Phase 05: Network Protocol** - BLOCKER
  - Cần stream pumps (pump_pty_to_quic, pump_quic_to_pty)
  - Cần heartbeat logic
  - Cần reconnection strategy
  - Nếu Phase 05 không complete → Terminal I/O không hoạt động

**Conclusion:** Phase 06 KHÔNG THỂ bắt đầu cho đến khi Phase 05 xong.

### 9. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| xterm.dart performance | Medium | High | Test large output early |
| Camera permission | Medium | Medium | Graceful fallback |
| FFI integration bugs | High | High | Extensive FFI tests |
| State complexity | Low | Medium | Riverpod generators |
| Virtual keyboard UX | Low | Low | Iterate on testing |
| iOS build issues | Medium | Medium | Test early on device |
| Android fragmentation | Low | Low | Test multiple versions |

**Highest Risk:** FFI integration bugs
**Mitigation:** Comprehensive FFI boundary tests + early device testing

### 10. Questions Unresolved

1. **Terminal resize:** Cần implement resize event?
2. **Clipboard:** Cần clipboard support?
3. **Wakelock state:** Persist preference?
4. **Saved hosts encryption:** Secure storage đủ?
5. **Error recovery:** Reconnect strategy?
6. **Buffer limits:** Avoid OOM?

**Recommendation:** Decide trong Phase 06 implementation, không block planning.

---

## Success Criteria Checklist

- [ ] QR scanner scans server QR code
- [ ] App connects + verifies fingerprint
- [ ] Terminal output streams continuously
- [ ] Terminal renders Catppuccin theme
- [ ] Virtual keyboard works (ESC, CTRL, Arrows)
- [ ] Connection state updates correctly
- [ ] Settings displays info
- [ ] All tests pass
- [ ] Runs on iOS + Android
- [ ] No crashes/memory leaks

---

## Next Steps

1. **BLOCKER:** Complete Phase 05 (Network Protocol) first
2. Generate FRB bindings: `flutter pub run build_runner build`
3. Implement QR scanner (Step 4)
4. Implement terminal UI (Step 6)
5. Test FFI boundary với Rust backend
6. Device testing (iOS + Android)
7. Proceed to Phase 07: Discovery & Auth

---

## Files Created

1. `plans/260107-1929-phase06-flutter-ui/phase-06-flutter-ui.md` - Detailed plan
2. `plans/reports/planner-260107-1929-phase06-flutter-ui.md` - This report

---

## Resources Referenced

### Tech Research:
- [xterm.dart - Best Flutter terminal 2025](https://pub.dev/packages/xterm)
- [mobile_scanner - QR scanning guide](https://pub.dev/packages/mobile_scanner)
- [Riverpod - State management 2025](https://riverpod.dev/)
- [Flutter Rust Bridge - FFI integration](https://cjycode.github.io/flutter_rust_bridge/)

### Internal Context:
- `crates/mobile_bridge/src/api.rs` - FFI functions ✅
- `crates/core/src/types/qr.rs` - QR payload format ✅
- `docs/project-roadmap.md` - Phase dependencies ✅
- Phase 04 plan - Mobile bridge implementation ✅
- Phase 05 plan - Network protocol (BLOCKER) ⏳

---

## Conclusion

Phase 06 plan **READY** cho implementation, nhưng **BLOCKED by Phase 05**.

**Key Takeaways:**
- Tech stack validated (xterm.dart, Riverpod, mobile_scanner)
- Architecture clear (feature-first, Riverpod generators)
- FFI integration strategy defined (BridgeWrapper pattern)
- Testing strategy comprehensive (3 layers)
- **Critical dependency:** Phase 05 MUST complete first

**Recommendation:** Focus on Phase 05 completion before starting Phase 06.
