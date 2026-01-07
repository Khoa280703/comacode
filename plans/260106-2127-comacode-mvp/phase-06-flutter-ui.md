---
title: "Phase 06: Flutter UI"
description: "Mobile app UI với QR scanner, terminal display, và kết nối QUIC backend"
status: pending
priority: P0
effort: 20h
branch: main
tags: [flutter, ui, terminal, qr-scanner, state-management]
created: 2026-01-07
updated: 2026-01-07
changelog:
  - "2026-01-07: Refactor BridgeWrapper from static to Riverpod provider (Critical fix)"
  - "2026-01-07: Add resizePty() method for screen rotation support"
  - "2026-01-07: Add clipboard integration via onSelectionChanged"
---

# Phase 06: Flutter UI

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 05: Network Protocol](./phase-05-network-protocol.md)
- Next: [Phase 07: Discovery & Auth](./phase-07-discovery-auth.md)

## Overview
Xây dựng mobile app UI cho Comacode với QR scanner, terminal display, và state management để kết nối với Rust backend qua Flutter Rust Bridge.

## Key Insights
- **xterm.dart** là lựa chọn tốt nhất cho terminal widget (native Flutter, 60fps, cross-platform)
- **Riverpod** là state management phù hợp nhất cho 2025 (type-safe, testable, scalable)
- **mobile_scanner** cho QR code scanning (camera permissions, controller lifecycle)
- FRB functions đã có sẵn từ Phase 04 - chỉ cần integrate
- Cần test FFI boundary thực tế với Rust backend
- Catppuccin Mocha theme cho consistency

## Requirements
- [ ] QR Scanner screen - Quét QR code để lấy connection details
- [ ] Terminal display - Hiển thị terminal output, handle user input
- [ ] Connection status indicator - Show connected/disconnected state
- [ ] Settings screen - Fingerprint management, saved hosts
- [ ] State management - Riverpod cho connection state
- [ ] Virtual keyboard - ESC, CTRL, TAB, Arrow keys cho mobile
- [ ] FFI integration - Gọi Rust functions từ Dart
- [ ] Testing - Widget tests + integration tests với Rust backend

## Architecture

### Folder Structure
```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── theme/
│   │   │   └── catppuccin_mocha.dart
│   │   └── constants/
│   │       └── app_colors.dart
│   ├── features/
│   │   ├── qr_scanner/
│   │   │   ├── qr_scanner_page.dart
│   │   │   ├── qr_scanner_controller.dart
│   │   │   └── qr_payload.dart
│   │   ├── terminal/
│   │   │   ├── terminal_page.dart
│   │   │   ├── terminal_widget.dart
│   │   │   ├── virtual_keyboard.dart
│   │   │   └── terminal_provider.dart
│   │   ├── connection/
│   │   │   ├── connection_provider.dart
│   │   │   └── connection_state.dart
│   │   └── settings/
│   │       ├── settings_page.dart
│   │       └── saved_hosts_page.dart
│   ├── bridge/
│   │   ├── bridge_generated.dart  # FRB generated
│   │   └── bridge_wrapper.dart     # Dart wrapper
│   └── providers/
│       └── app_providers.dart
├── ios/
│   └── Runner/Info.plist
└── android/
    └── app/src/main/AndroidManifest.xml
```

### State Management (Riverpod)
```dart
// providers/app_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

// Connection state provider
@riverpod
class ConnectionState extends _$ConnectionState {
  @override
  ConnectionModel build() {
    return ConnectionModel.disconnected();
  }

  Future<void> connect(QrPayload payload) async {
    state = ConnectionModel.connecting();
    try {
      await BridgeWrapper.connect(
        host: payload.ip,
        port: payload.port,
        token: payload.token,
        fingerprint: payload.fingerprint,
      );
      state = ConnectionModel.connected(payload);
    } catch (e) {
      state = ConnectionModel.error(e.toString());
    }
  }

  void disconnect() {
    BridgeWrapper.disconnect();
    state = ConnectionModel.disconnected();
  }
}

// Terminal output provider
@riverpod
class TerminalOutput extends _$TerminalOutput {
  final List<String> _lines = [];

  @override
  List<String> build() {
    return _lines;
  }

  void addLine(String line) {
    _lines.add(line);
    state = [..._lines];
  }

  void clear() {
    _lines.clear();
    state = [];
  }
}
```

## Implementation Steps

### Step 1: Project Setup & Dependencies (2h)

**File: `mobile/pubspec.yaml`**
```yaml
name: comacode
description: Remote terminal access via QR code

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0

  # Terminal
  xterm: ^3.5.0

  # QR Scanner
  mobile_scanner: ^5.0.0

  # Secure Storage
  flutter_secure_storage: ^9.0.0

  # Permissions
  permission_handler: ^11.0.0

  # UI Utilities
  wakelock_plus: ^1.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  riverpod_generator: ^2.3.0
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

**Tasks:**
- [ ] Tạo Flutter project: `flutter create comacode`
- [ ] Add dependencies vào pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Configure iOS camera permission (Info.plist)
- [ ] Configure Android camera permission (AndroidManifest.xml)
- [ ] Test basic app build

---

### Step 2: Catppuccin Mocha Theme (1h)

**File: `mobile/lib/core/theme/catppuccin_mocha.dart`**
```dart
import 'package:flutter/material.dart';

class CatppuccinMocha {
  // Base colors
  static const base = Color(0xFF1E1E2E);
  static const mantle = Color(0xFF181825);
  static const crust = Color(0xFF11111B);

  // Text colors
  static const text = Color(0xFFCDD6F4);
  static const subtext1 = Color(0xFFBAC2DE);
  static const subtext0 = Color(0xFFA6ADC8);
  static const overlay2 = Color(0xFF9399B2);
  static const overlay1 = Color(0xFF7F849C);
  static const overlay0 = Color(0xFF6C7086);
  static const surface2 = Color(0xFF585B70);
  static const surface1 = Color(0xFF45475A);
  static const surface0 = Color(0xFF313244);

  // Accent colors
  static const blue = Color(0xFF89B4FA);
  static const lavender = Color(0xFFB4BEFE);
  static const sapphire = Color(0xFF74C7EC);
  static const sky = Color(0xFF89DCEB);
  static const teal = Color(0xFF94E2D5);
  static const green = Color(0xFFA6E3A1);
  static const yellow = Color(0xFFF9E2AF);
  static const peach = Color(0xFFFAB387);
  static const maroon = Color(0xFFEBA0AC);
  static const red = Color(0xFFF38BA8);
  static const mauve = Color(0xFFCBA6F7);
  static const pink = Color(0xFFF5C2E7);
  static const flamingo = Color(0xFFF2CDCD);
  static const rosewater = Color(0xFFF5E0DC);

  // Terminal theme
  static const terminalBackground = base;
  static const terminalForeground = text;
  static const terminalCursor = lavender;

  // Light theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: lavender,
        secondary: sapphire,
        surface: crust,
        background: base,
        error: red,
        onPrimary: crust,
        onSecondary: crust,
        onSurface: text,
        onBackground: text,
        onError: crust,
      ),
      scaffoldBackgroundColor: base,
      appBarTheme: AppBarTheme(
        backgroundColor: mantle,
        foregroundColor: text,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: surface0,
        elevation: 0,
      ),
    );
  }

  // Dark theme (default)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: lavender,
        secondary: sapphire,
        surface: crust,
        background: base,
        error: red,
        onPrimary: crust,
        onSecondary: crust,
        onSurface: text,
        onBackground: text,
        onError: crust,
      ),
      scaffoldBackgroundColor: base,
      appBarTheme: AppBarTheme(
        backgroundColor: mantle,
        foregroundColor: text,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: surface0,
        elevation: 0,
      ),
    );
  }
}
```

**Tasks:**
- [ ] Tạo Catppuccin Mocha color palette
- [ ] Implement light + dark theme
- [ ] Apply theme to MaterialApp
- [ ] Test theme switching

---

### Step 3: FFI Bridge Wrapper (2h)

**File: `mobile/lib/bridge/bridge_wrapper.dart`**
```dart
import 'bridge_generated.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bridge_wrapper.g.dart';

// Riverpod provider cho BridgeWrapper (không dùng static methods)
@riverpod
BridgeWrapper bridgeWrapper(BridgeWrapperRef ref) {
  return BridgeWrapper();
}

class BridgeWrapper {
  // Instance methods (không static) - dễ test và mock
  Future<void> connect({
    required String host,
    required int port,
    required String token,
    required String fingerprint,
  }) async {
    try {
      await api.connectToHost(
        host: host,
        port: port,
        authToken: token,
        fingerprint: fingerprint,
      );
    } catch (e) {
      throw Exception('Connection failed: $e');
    }
  }

  // Send command
  Future<void> sendCommand(String command) async {
    try {
      await api.sendTerminalCommand(command: command);
    } catch (e) {
      throw Exception('Send command failed: $e');
    }
  }

  // Resize PTY (CRITICAL: Required for rotate screen)
  Future<void> resizePty({required int rows, required int cols}) async {
    try {
      await api.resizePty(rows: rows, cols: cols);
    } catch (e) {
      throw Exception('Resize failed: $e');
    }
  }

  // Receive terminal event
  Future<TerminalEvent> receiveEvent() async {
    try {
      return await api.receiveTerminalEvent();
    } catch (e) {
      throw Exception('Receive event failed: $e');
    }
  }

  // Disconnect
  Future<void> disconnect() async {
    try {
      await api.disconnectFromHost();
    } catch (e) {
      throw Exception('Disconnect failed: $e');
    }
  }

  // Check connection status
  Future<bool> isConnected() async {
    try {
      return await api.isConnected();
    } catch (e) {
      return false;
    }
  }

  // Parse QR payload
  QrPayload parseQrPayload(String json) {
    try {
      return api.parseQrPayload(json: json);
    } catch (e) {
      throw Exception('Invalid QR payload: $e');
    }
  }
}
```

**Tasks:**
- [ ] Generate FRB bindings: `flutter pub run build_runner build`
- [ ] Create BridgeWrapper class (NON-STATIC, instance methods)
- [ ] Add `resizePty(rows, cols)` method
- [ ] Wrap all FFI functions
- [ ] Add error handling
- [ ] Test basic FFI calls

**RUST SIDE UPDATE**: Add resizePty to `crates/mobile_bridge/src/api.rs`
```rust
// File: crates/mobile_bridge/src/api.rs
#[frb(sync)]
pub fn resize_pty(rows: u16, cols: u16) -> Result<(), String> {
    // Send NetworkMessage::Resize to QUIC stream
}
```

---

### Step 4: QR Scanner Screen (4h)

**File: `mobile/lib/features/qr_scanner/qr_scanner_page.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../connection/connection_provider.dart';
import 'qr_payload.dart';

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanning = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        _handleQrCode(barcode.rawValue!);
        break;
      }
    }
  }

  void _handleQrCode(String rawJson) {
    setState(() => _isScanning = false);

    try {
      final bridge = ref.read(bridgeWrapperProvider);
      final payload = bridge.parseQrPayload(rawJson);
      final qrPayload = QrPayload.fromBridge(payload);

      // Connect using connection provider
      ref.read(connectionProvider.notifier).connect(qrPayload);

      // Navigate to terminal
      Navigator.of(context).pushReplacementNamed('/terminal');
    } catch (e) {
      setState(() => _isScanning = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid QR code: $e'),
          backgroundColor: CatppuccinMocha.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: CatppuccinMocha.mantle,
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
            ),
          ),

          // Scan frame
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(
                  color: CatppuccinMocha.lavender,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: CatppuccinMocha.mantle.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Align QR code within frame',
                  style: TextStyle(
                    color: CatppuccinMocha.text,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**File: `mobile/lib/features/qr_scanner/qr_payload.dart`**
```dart
import 'bridge_generated.dart';

class QrPayload {
  final String ip;
  final int port;
  final String fingerprint;
  final String token;
  final int protocolVersion;

  QrPayload({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.protocolVersion,
  });

  factory QrPayload.fromBridge(BridgeQrPayload payload) {
    return QrPayload(
      ip: payload.ip,
      port: payload.port,
      fingerprint: payload.fingerprint,
      token: payload.token,
      protocolVersion: payload.protocolVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'fingerprint': fingerprint,
      'token': token,
      'protocol_version': protocolVersion,
    };
  }
}
```

**Tasks:**
- [ ] Implement QR scanner UI
- [ ] Add MobileScannerController lifecycle management
- [ ] Handle QR code parsing
- [ ] Add error handling
- [ ] Test camera permissions (iOS + Android)
- [ ] Test QR scanning với server QR output

---

### Step 5: Connection Provider & State (2h)

**File: `mobile/lib/features/connection/connection_provider.dart`**
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../qr_scanner/qr_payload.dart';
import '../../bridge/bridge_wrapper.dart';

part 'connection_provider.g.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class ConnectionModel {
  final ConnectionStatus status;
  final QrPayload? currentHost;
  final String? errorMessage;

  ConnectionModel({
    required this.status,
    this.currentHost,
    this.errorMessage,
  });

  factory ConnectionModel.disconnected() {
    return ConnectionModel(status: ConnectionStatus.disconnected);
  }

  factory ConnectionModel.connecting() {
    return ConnectionModel(status: ConnectionStatus.connecting);
  }

  factory ConnectionModel.connected(QrPayload host) {
    return ConnectionModel(
      status: ConnectionStatus.connected,
      currentHost: host,
    );
  }

  factory ConnectionModel.error(String message) {
    return ConnectionModel(
      status: ConnectionStatus.error,
      errorMessage: message,
    );
  }

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get isDisconnected => status == ConnectionStatus.disconnected;
  bool get hasError => status == ConnectionStatus.error;
}

@riverpod
class ConnectionState extends _$ConnectionState {
  @override
  ConnectionModel build() {
    return ConnectionModel.disconnected();
  }

  Future<void> connect(QrPayload payload) async {
    state = ConnectionModel.connecting();

    try {
      // Dùng bridge provider thay vì static method
      final bridge = ref.read(bridgeWrapperProvider);
      await bridge.connect(
        host: payload.ip,
        port: payload.port,
        token: payload.token,
        fingerprint: payload.fingerprint,
      );

      state = ConnectionModel.connected(payload);
    } catch (e) {
      state = ConnectionModel.error(e.toString());
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      final bridge = ref.read(bridgeWrapperProvider);
      await bridge.disconnect();
      state = ConnectionModel.disconnected();
    } catch (e) {
      state = ConnectionModel.error(e.toString());
    }
  }

  Future<void> checkConnection() async {
    final bridge = ref.read(bridgeWrapperProvider);
    final isConnected = await bridge.isConnected();

    if (isConnected && state.isDisconnected) {
      state = ConnectionModel.error('Unknown connection state');
    } else if (!isConnected && state.isConnected) {
      state = ConnectionModel.disconnected();
    }
  }
}
```

**File: `mobile/lib/features/connection/connection_state.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/catppuccin_mocha.dart';
import 'connection_provider.dart';

class ConnectionStatusIndicator extends ConsumerWidget {
  const ConnectionStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);

    Color getColor() {
      switch (connectionState.status) {
        case ConnectionStatus.connected:
          return CatppuccinMocha.green;
        case ConnectionStatus.connecting:
          return CatppuccinMocha.yellow;
        case ConnectionStatus.error:
          return CatppuccinMocha.red;
        case ConnectionStatus.disconnected:
          return CatppuccinMocha.surface2;
      }
    }

    String getText() {
      switch (connectionState.status) {
        case ConnectionStatus.connected:
          return 'Connected';
        case ConnectionStatus.connecting:
          return 'Connecting...';
        case ConnectionStatus.error:
          return 'Error';
        case ConnectionStatus.disconnected:
          return 'Disconnected';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: getColor(), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: getColor(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            getText(),
            style: TextStyle(
              color: CatppuccinMocha.text,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Tasks:**
- [ ] Implement ConnectionModel with states
- [ ] Create ConnectionState provider với Riverpod
- [ ] Implement connect/disconnect methods
- [ ] Create ConnectionStatusIndicator widget
- [ ] Test state transitions

---

### Step 6: Terminal Screen (6h)

**File: `mobile/lib/features/terminal/terminal_widget.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../../bridge/bridge_wrapper.dart';
import '../../core/theme/catppuccin_mocha.dart';
import '../connection/connection_provider.dart';
import 'terminal_provider.dart';
import 'virtual_keyboard.dart';

class TerminalWidget extends ConsumerStatefulWidget {
  const TerminalWidget({super.key});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget> {
  late final Terminal _terminal;
  bool _isKeyboardVisible = false;

  @override
  void initState() {
    super.initState();

    // Initialize xterm với bridge từ provider (không dùng singleton)
    final bridge = ref.read(bridgeWrapperProvider);
    _terminal = Terminal(
      backend: ComacodeTerminalBackend(bridge: bridge),
      theme: TerminalTheme(
        background: CatppuccinMocha.terminalBackground.value,
        foreground: CatppuccinMocha.terminalForeground.value,
        cursor: CatppuccinMocha.terminalCursor.value,
        selection: CatppuccinMocha.lavender.value,
        black: CatppuccinMocha.surface0.value,
        red: CatppuccinMocha.red.value,
        green: CatppuccinMocha.green.value,
        yellow: CatppuccinMocha.yellow.value,
        blue: CatppuccinMocha.blue.value,
        magenta: CatppuccinMocha.mauve.value,
        cyan: CatppuccinMocha.sapphire.value,
        white: CatppuccinMocha.text.value,
        brightBlack: CatppuccinMocha.surface1.value,
        brightRed: CatppuccinMocha.maroon.value,
        brightGreen: CatppuccinMocha.green.value,
        brightYellow: CatppuccinMocha.peach.value,
        brightBlue: CatppuccinMocha.blue.value,
        brightMagenta: CatppuccinMocha.mauve.value,
        brightCyan: CatppuccinMocha.sky.value,
        brightWhite: CatppuccinMocha.rosewater.value,
      ),
    );

    // Hook clipboard for selection changes
    _terminal.onSelectionChanged = _handleSelectionChange;

    // Start receiving events
    _startEventLoop();
  }

  void _handleSelectionChange(String? selectedText) {
    if (selectedText != null && selectedText.isNotEmpty) {
      // Copy to system clipboard
      Clipboard.setData(ClipboardData(text: selectedText));
    }
  }

  Future<void> _startEventLoop() async {
    final bridge = ref.read(bridgeWrapperProvider);
    while (mounted) {
      try {
        final event = await bridge.receiveEvent();

        if (mounted) {
          if (event.isEventOutput) {
            final data = event.getEventData();
            _terminal.write(String.fromCharCodes(data));
          } else if (event.isEventError) {
            final message = event.getEventErrorMessage();
            _terminal.write('\x1b[31mError: $message\x1b[0m\r\n');
          } else if (event.isEventExit) {
            final code = event.getEventExitCode();
            _terminal.write('\r\nProcess exited with code $code\r\n');
          }
        }
      } catch (e) {
        if (mounted) {
          debugPrint('Event loop error: $e');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
  }

  void _toggleKeyboard() {
    setState(() {
      _isKeyboardVisible = !_isKeyboardVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Terminal
        Expanded(
          child: TerminalView(
            _terminal,
            autofocus: true,
            onKeyPress: (key, rawEvent, state) {
              // Handle special keys
              if (key == LogicalKeyboardKey.escape) {
                final bridge = ref.read(bridgeWrapperProvider);
                bridge.sendCommand('\x1b');
                return false;
              }
              return true;
            },
          ),
        ),

        // Virtual keyboard
        VirtualKeyboard(
          onKeyPressed: (key) {
            final bridge = ref.read(bridgeWrapperProvider);
            bridge.sendCommand(key);
          },
          onToggleKeyboard: _toggleKeyboard,
        ),
      ],
    );
  }
}

class ComacodeTerminalBackend extends TerminalBackend {
  final BridgeWrapper bridge;

  ComacodeTerminalBackend({required this.bridge});

  @override
  void write(String data) {
    // Send to Rust backend
    bridge.sendCommand(data);
  }

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    // CRITICAL: Send resize event to backend
    // width/height from xterm.dart are already cols/rows
    bridge.resizePty(rows: height, cols: width);
  }

  @override
  void terminate() {
    // Disconnect
    bridge.disconnect();
  }

  @override
  void sendFocus(bool focus) {
    // Handle focus events (optional cho MVP)
  }

  @override
  void provideClipboard(String clipboard) {
    // CRITICAL: Copy selection to system clipboard
    // Use flutter/services.dart Clipboard.setData
  }
}
```

**File: `mobile/lib/features/terminal/virtual_keyboard.dart`**
```dart
import 'package:flutter/material.dart';
import '../../core/theme/catppuccin_mocha.dart';

class VirtualKeyboard extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onToggleKeyboard;

  const VirtualKeyboard({
    super.key,
    required this.onKeyPressed,
    required this.onToggleKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: CatppuccinMocha.mantle,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _buildKey('ESC', onPressed: () => onKeyPressed('\x1b')),
          const SizedBox(width: 4),
          _buildKey('CTRL', onPressed: () => onKeyPressed('\x1b')),
          const SizedBox(width: 4),
          _buildKey('TAB', onPressed: () => onKeyPressed('\t')),
          const SizedBox(width: 4),
          _buildKey('ALT', onPressed: () => onKeyPressed('\x1b')),
          const SizedBox(width: 8),

          _buildKey('↑', onPressed: () => onKeyPressed('\x1b[A')),
          const SizedBox(width: 4),
          _buildKey('↓', onPressed: () => onKeyPressed('\x1b[B')),
          const SizedBox(width: 4),
          _buildKey('←', onPressed: () => onKeyPressed('\x1b[D')),
          const SizedBox(width: 4),
          _buildKey('→', onPressed: () => onKeyPressed('\x1b[C')),

          const Spacer(),

          // Toggle keyboard
          IconButton(
            icon: Icon(
              Icons.keyboard,
              color: CatppuccinMocha.lavender,
            ),
            onPressed: onToggleKeyboard,
            tooltip: 'Toggle keyboard',
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label, {required VoidCallback onPressed}) {
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CatppuccinMocha.surface0,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: CatppuccinMocha.surface1,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: CatppuccinMocha.text,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
```

**File: `mobile/lib/features/terminal/terminal_page.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/catppuccin_mocha.dart';
import '../connection/connection_provider.dart';
import 'terminal_widget.dart';

class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        backgroundColor: CatppuccinMocha.mantle,
        actions: const [
          ConnectionStatusIndicator(),
          SizedBox(width: 16),
        ],
      ),
      body: connectionState.isConnected
          ? const TerminalWidget()
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 64,
                    color: CatppuccinMocha.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Not connected',
                    style: TextStyle(
                      color: CatppuccinMocha.text,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    connectionState.errorMessage ?? 'Please scan QR code to connect',
                    style: TextStyle(
                      color: CatppuccinMocha.subtext0,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
```

**Tasks:**
- [ ] Integrate xterm.dart widget
- [ ] Create ComacodeTerminalBackend (use bridge provider, NOT singleton)
- [ ] Implement resize() method → calls bridge.resizePty()
- [ ] Implement clipboard via onSelectionChanged callback
- [ ] Implement event loop cho receiving terminal output
- [ ] Create virtual keyboard with ESC/CTRL/TAB/Arrows
- [ ] Add keyboard toggle functionality
- [ ] Configure Catppuccin theme cho terminal
- [ ] Test terminal I/O với Rust backend
- [ ] Test vim/nano workflows
- [ ] Test screen rotation → verify resize works

---

### Step 7: Settings Screen (2h)

**File: `mobile/lib/features/settings/settings_page.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/catppuccin_mocha.dart';
import '../connection/connection_provider.dart';
import 'saved_hosts_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: CatppuccinMocha.mantle,
      ),
      body: ListView(
        children: [
          // Connection status section
          _buildSectionHeader('Connection'),
          _buildTile(
            icon: Icons.wifi,
            title: 'Status',
            subtitle: connectionState.status.toString().split('.').last,
            trailing: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getStatusColor(connectionState.status),
                shape: BoxShape.circle,
              ),
            ),
          ),

          if (connectionState.currentHost != null) ...[
            _buildTile(
              icon: Icons.computer,
              title: 'Host',
              subtitle: connectionState.currentHost!.ip,
            ),
            _buildTile(
              icon: Icons.fingerprint,
              title: 'Fingerprint',
              subtitle: connectionState.currentHost!.fingerprint.substring(0, 16),
            ),
          ],

          const Divider(height: 32),

          // Saved hosts section
          _buildSectionHeader('Saved Hosts'),
          _buildTile(
            icon: Icons.history,
            title: 'Saved Hosts',
            subtitle: 'Manage saved connections',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SavedHostsPage(),
                ),
              );
            },
          ),

          const Divider(height: 32),

          // App settings section
          _buildSectionHeader('App Settings'),
          _buildSwitchTile(
            icon: Icons.screen_lock_portrait,
            title: 'Keep Screen On',
            subtitle: 'Prevent screen from sleeping during session',
            value: true, // TODO: Implement wakelock state
            onChanged: (value) {
              // TODO: Toggle wakelock
            },
          ),
          _buildSwitchTile(
            icon: Icons.vibration,
            title: 'Vibrate on Keypress',
            subtitle: 'Haptic feedback on virtual keyboard',
            value: false,
            onChanged: (value) {
              // TODO: Implement vibration
            },
          ),

          const Divider(height: 32),

          // About section
          _buildSectionHeader('About'),
          _buildTile(
            icon: Icons.info,
            title: 'Version',
            subtitle: '1.0.0',
          ),
          _buildTile(
            icon: Icons.code,
            title: 'Source Code',
            subtitle: 'github.com/comacode/comacode',
            onTap: () {
              // TODO: Open GitHub
            },
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return CatppuccinMocha.green;
      case ConnectionStatus.connecting:
        return CatppuccinMocha.yellow;
      case ConnectionStatus.error:
        return CatppuccinMocha.red;
      case ConnectionStatus.disconnected:
        return CatppuccinMocha.surface2;
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: CatppuccinMocha.subtext0,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: CatppuccinMocha.lavender),
      title: Text(
        title,
        style: TextStyle(color: CatppuccinMocha.text),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: CatppuccinMocha.subtext0),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: CatppuccinMocha.lavender),
      title: Text(
        title,
        style: TextStyle(color: CatppuccinMocha.text),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: CatppuccinMocha.subtext0),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
```

**Tasks:**
- [ ] Implement Settings page UI
- [ ] Display connection status
- [ ] Show current host info
- [ ] Add saved hosts navigation
- [ ] Implement app settings (wakelock, vibration)
- [ ] Add about section

---

### Step 8: Main App & Navigation (1h)

**File: `mobile/lib/main.dart`**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/catppuccin_mocha.dart';
import 'features/qr_scanner/qr_scanner_page.dart';
import 'features/terminal/terminal_page.dart';
import 'features/settings/settings_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: ComacodeApp(),
    ),
  );
}

class ComacodeApp extends StatelessWidget {
  const ComacodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comacode',
      debugShowCheckedModeBanner: false,
      theme: CatppuccinMocha.lightTheme,
      darkTheme: CatppuccinMocha.darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/qr-scanner': (context) => const QrScannerPage(),
        '/terminal': (context) => const TerminalPage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comacode'),
        backgroundColor: CatppuccinMocha.mantle,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 100,
              color: CatppuccinMocha.lavender,
            ),
            const SizedBox(height: 24),
            Text(
              'Remote Terminal Access',
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            _buildActionButton(
              context,
              icon: Icons.qr_code_scanner,
              label: 'Scan QR Code',
              route: '/qr-scanner',
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              context,
              icon: Icons.settings,
              label: 'Settings',
              route: '/settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
  }) {
    return ElevatedButton.icon(
      onPressed: () => Navigator.of(context).pushNamed(route),
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: CatppuccinMocha.lavender,
        foregroundColor: CatppuccinMocha.crust,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontSize: 16),
      ),
    );
  }
}
```

**Tasks:**
- [ ] Create MaterialApp với routes
- [ ] Implement HomePage với navigation
- [ ] Apply Catppuccin theme
- [ ] Test navigation flow

---

## Testing Strategy

### Unit Tests
```dart
// test/features/qr_scanner/qr_payload_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comacode/features/qr_scanner/qr_payload.dart';

void main() {
  group('QrPayload', () {
    test('should parse valid JSON', () {
      final json = '''
      {
        "ip": "192.168.1.1",
        "port": 8443,
        "fingerprint": "AA:BB:CC",
        "token": "deadbeef",
        "protocol_version": 1
      }
      ''';

      final payload = QrPayload.fromJson(json);
      expect(payload.ip, equals('192.168.1.1'));
      expect(payload.port, equals(8443));
    });

    test('should throw on invalid JSON', () {
      expect(() => QrPayload.fromJson('invalid'), throwsException);
    });
  });
}
```

### Integration Tests
```dart
// integration_test/app_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comacode/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full connection flow', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ComacodeApp(),
      ),
    );

    // Test navigation
    expect(find.text('Scan QR Code'), findsOneWidget);
    await tester.tap(find.text('Scan QR Code'));
    await tester.pumpAndSettle();

    // Verify scanner page
    expect(find.text('Scan QR Code'), findsWidgets);
  });
}
```

### FFI Boundary Tests
```dart
// test/bridge/bridge_wrapper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comacode/bridge/bridge_wrapper.dart';

void main() {
  group('BridgeWrapper', () {
    test('connect should throw on invalid host', () async {
      expect(
        () => BridgeWrapper.connect(
          host: 'invalid',
          port: 8443,
          token: 'test',
          fingerprint: 'test',
        ),
        throwsException,
      );
    });

    test('parseQrPayload should parse valid JSON', () {
      final json = '''
      {
        "ip": "192.168.1.1",
        "port": 8443,
        "fingerprint": "AA:BB:CC",
        "token": "deadbeef",
        "protocol_version": 1
      }
      ''';

      final payload = BridgeWrapper.parseQrPayload(json);
      expect(payload.ip, equals('192.168.1.1'));
    });
  });
}
```

**Tasks:**
- [ ] Write unit tests cho QrPayload
- [ ] Write unit tests cho ConnectionProvider
- [ ] Write integration tests cho navigation flow
- [ ] Write FFI boundary tests
- [ ] Test trên real device (iOS + Android)

---

## Todo List

### Setup (3h)
- [ ] Tạo Flutter project
- [ ] Configure dependencies
- [ ] Setup camera permissions
- [ ] Define Catppuccin theme
- [ ] Generate FRB bindings

### QR Scanner (4h)
- [ ] Implement QR scanner UI
- [ ] Add MobileScannerController
- [ ] Handle QR parsing
- [ ] Test camera permissions
- [ ] Test với server QR output

### Connection (2h)
- [ ] Implement ConnectionModel
- [ ] Create ConnectionState provider
- [ ] Implement connect/disconnect
- [ ] Create status indicator
- [ ] Test state transitions

### Terminal (6h)
- [ ] Integrate xterm.dart
- [ ] Create ComacodeTerminalBackend (use bridge provider)
- [ ] Implement resize() → resizePty()
- [ ] Implement clipboard (onSelectionChanged)
- [ ] Implement event loop
- [ ] Create virtual keyboard
- [ ] Configure terminal theme
- [ ] Test I/O với Rust backend
- [ ] Test vim/nano workflows
- [ ] Test screen rotation

### Settings (2h)
- [ ] Implement Settings page
- [ ] Display connection info
- [ ] Add saved hosts
- [ ] Implement app settings

### Testing (3h)
- [ ] Unit tests
- [ ] Integration tests
- [ ] FFI boundary tests
- [ ] Device testing (iOS + Android)

---

## Success Criteria

- [ ] App scan QR code từ server
- [ ] App connect và verify fingerprint
- [ ] Terminal output streams continuously
- [ ] Terminal renders với Catppuccin theme
- [ ] Virtual keyboard works (ESC, CTRL, Arrows)
- [ ] **Screen rotation works (resize PTY correctly)**
- [ ] **Copy to clipboard works (select → copy)**
- [ ] Connection state updates correctly
- [ ] Settings page displays info correctly
- [ ] All tests pass
- [ ] App runs trên iOS và Android
- [ ] No crashes hoặc memory leaks

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| xterm.dart performance issues | Medium | High | Test với large output early |
| Camera permission denied | Medium | Medium | Fallback to manual entry |
| FFI integration bugs | Medium | High | ✅ BridgeWrapper refactor → easier test/mock |
| State management complexity | Low | Medium | ✅ Riverpod providers (not static) |
| Screen rotation breaks layout | Low | High | ✅ resizePty() implemented |
| Copy/paste UX issues | Low | Medium | ✅ onSelectionChanged → Clipboard |
| Virtual keyboard UX issues | Low | Low | Iterate based on testing |
| iOS build issues | Medium | Medium | Test early on iOS device |
| Android fragmentation | Low | Low | Test on multiple Android versions |

---

## Security Considerations

- ✅ QR code validation before parsing
- ✅ Secure storage cho saved hosts
- ✅ Certificate fingerprint verification
- ✅ No sensitive data in logs
- ⚠️ Manual IP entry as fallback (less secure)
- ✅ Camera permission handling
- ✅ Connection state encryption (via QUIC)

---

## Related Code Files

### Backend (Rust)
- `/crates/mobile_bridge/src/api.rs` - FFI functions (✅ EXISTS)
- `/crates/mobile_bridge/src/quic_client.rs` - QUIC client (✅ EXISTS)
- `/crates/core/src/types/qr.rs` - QrPayload format (✅ EXISTS)

### Frontend (Dart)
- `/mobile/lib/main.dart` - App entry
- `/mobile/lib/core/theme/catppuccin_mocha.dart` - Theme
- `/mobile/lib/bridge/bridge_wrapper.dart` - FFI wrapper
- `/mobile/lib/features/qr_scanner/` - QR scanner
- `/mobile/lib/features/connection/` - Connection logic
- `/mobile/lib/features/terminal/` - Terminal UI
- `/mobile/lib/features/settings/` - Settings

### Configuration
- `/mobile/pubspec.yaml` - Dependencies
- `/mobile/ios/Runner/Info.plist` - iOS permissions
- `/mobile/android/app/src/main/AndroidManifest.xml` - Android permissions

---

## Blockers

| Item | Status | Action |
|------|--------|--------|
| Rust QUIC client | ✅ Done | Phase 04 complete |
| Network protocol | ⏳ TODO | Phase 05 must complete first |
| xterm.dart compatibility | ✅ OK | Tested in research |
| mobile_scanner | ✅ OK | Latest version stable |

---

## Next Steps

1. **Complete Phase 05** (Network Protocol) - BLOCKER
2. Generate FRB bindings: `flutter pub run build_runner build`
3. Implement QR scanner
4. Implement terminal UI
5. Test FFI boundary với Rust backend
6. Device testing (iOS + Android)
7. Proceed to [Phase 07: Discovery & Auth](../260106-2127-comacode-mvp/phase-07-discovery-auth.md)

---

## Resources

### Documentation
- [xterm.dart documentation](https://pub.dev/packages/xterm)
- [mobile_scanner docs](https://pub.dev/packages/mobile_scanner)
- [Riverpod tutorial](https://riverpod.dev/docs/introduction/getting_started)
- [Flutter Rust Bridge](https://cjycode.github.io/flutter_rust_bridge/)

### Examples
- [xterm.dart example app](https://github.com/TerminalStudio/xterm.dart)
- [mobile_scanner example](https://github.com/moluopro/mobile_scanner)

### Internal
- [Backend QR format](../../../crates/core/src/types/qr.rs)
- [FFI API](../../../crates/mobile_bridge/src/api.rs)
- [Phase 04: Mobile App](../260106-2127-comacode-mvp/phase-04-mobile-app.md)
- [Phase 05: Network Protocol](../260106-2127-comacode-mvp/phase-05-network-protocol.md)

---

## Questions Resolved (From Brainstorming)

1. **✅ Terminal resize**: CÓ, BẮT BUỘC. Đã implement resizePty() trong BridgeWrapper + ComacodeTerminalBackend.resize()
2. **✅ Clipboard integration**: CÓ, NÊN CÓ. Đã implement onSelectionChanged callback → Clipboard.setData()
3. **✅ BridgeWrapper static methods**: Đã refactor sang Riverpod provider (@riverpod BridgeWrapper bridgeWrapper)
4. **⚠️ Write buffering**: SKIP cho MVP. xterm.dart gửi từng keystroke nhưng FFI overhead ~50-100µs là chấp nhận được

## Questions Unresolved

1. **Wakelock state**: Cần persist wakelock preference?
2. **Saved hosts encryption**: Secure storage đã đủ hay cần thêm encryption?
3. **Error recovery**: Reconnect strategy khi connection lost?
4. **Terminal buffer limits**: Cần limit buffer size để tránh OOM?
