---
title: "Phase 04: Mobile App (Flutter)"
description: "iOS/Android app with terminal UI, connects to Host Agent via QUIC"
status: pending
priority: P0
effort: 16h
branch: main
tags: [flutter, ui, terminal, quic-client]
created: 2026-01-06
---

# Phase 04: Mobile App (Flutter)

## Context
- [Parent Plan](./plan.md)
- Previous: [Phase 03](./phase-03-host-agent.md)

## Overview
Build Flutter mobile app with terminal UI, QUIC client, and FFI bridge to Rust core.

## Key Insights
- `xterm_flutter` for terminal emulation
- QUIC client via Rust FFI (no pure Dart QUIC lib)
- `flutter_rust_bridge` for async callbacks
- Catppuccin Mocha theme for developer aesthetics
- Haptic feedback for typing experience

## Requirements
- Terminal UI with xterm_flutter
- QUIC client (via Rust FFI)
- Connection state management
- Keyboard input handling
- Virtual terminal size config
- Session management (connect/disconnect)
- Error display & recovery
- Platform permissions (network)

## Architecture
```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart              # App entry
│   ├── core/
│   │   ├── theme.dart        # Catppuccin colors
│   │   └── constants.dart
│   ├── features/
│   │   ├── terminal/
│   │   │   ├── terminal_page.dart
│   │   │   ├── terminal_widget.dart
│   │   │   └── terminal_controller.dart
│   │   ├── connection/
│   │   │   ├── discovery_page.dart
│   │   │   └── connection_provider.dart
│   │   └── settings/
│   │       └── settings_page.dart
│   └── bridge/
│       ├── bridge_generated.dart  # FRB generated
│       └── bridge.dart            # Wrapper
├── ios/                         # iOS config
└── android/                     # Android config
```

## Implementation Steps

### Step 1: Project Setup & Theme (2h)
```dart
// lib/core/theme.dart
import 'package:flutter/material.dart';

class CatppuccinMocha {
  static const base = Color(0xFF1E1E2E);
  static const surface = Color(0xFF313244);
  static const primary = Color(0xFFCBA6F7); // Mauve
  static const text = Color(0xFFCDD6F4);
  static const green = Color(0xFFA6E3A1);
  static const red = Color(0xFFF38BA8);
  static const yellow = Color(0xFFF9E2AF);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        background: base,
        surface: surface,
        primary: primary,
      ),
      scaffoldBackgroundColor: base,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
      ),
    );
  }
}
```

**Tasks**:
- [ ] Create Flutter app with `flutter create`
- [ ] Add dependencies: `xterm_flutter`, `provider`, `flutter_rust_bridge`
- [ ] Define Catppuccin Mocha color palette
- [ ] Set up app theme
- [ ] Configure iOS/Android permissions

### Step 2: FRB Integration (3h)
```dart
// lib/bridge/bridge.dart
import 'bridge_generated.dart';

class ComacodeBridge {
  static const _api = ComacodeCoreApi();

  /// Create terminal command from text
  static Future<TerminalCommand> createCommand(String text) async {
    return _api.createCommand(text);
  }

  /// Connect to host agent
  static Future<void> connect(String host, int port) async {
    await _api.connectToHost(host: host, port: port);
  }

  /// Send command to host
  static Future<void> sendCommand(TerminalCommand cmd) async {
    await _api.sendCommand(cmd: cmd);
  }

  /// Stream terminal output
  static Stream<TerminalEvent> get terminalEventStream {
    return _api.getTerminalEventStream();
  }
}
```

**Tasks**:
- [ ] Add FFI package to `pubspec.yaml`
- [ ] Generate Dart bindings from Rust
- [ ] Create wrapper class for bridge API
- [ ] Test FFI call from Dart
- [ ] Handle async streams from Rust

### Step 3: Terminal UI (4h)
```dart
// lib/features/terminal/terminal_widget.dart
import 'package:xterm/flutter.dart';
import 'package:xterm/ui.dart' as ui;

class TerminalWidget extends StatefulWidget {
  final TerminalController controller;

  const TerminalWidget({super.key, required this.controller});

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late final terminal = ui.Terminal(
    controller: widget.controller,
    theme: ui.TerminalTheme(
      background: CatppuccinMocha.base.value,
      foreground: CatppuccinMocha.text.value,
      cursor: CatppuccinMocha.primary.value,
      selection: CatppuccinMocha.primary.withOpacity(0.3).value,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ui.TerminalView(
      terminal: terminal,
      onKeyPressed: (key) {
        // Send keystroke to Rust bridge
        ComacodeBridge.sendCommand(
          TerminalCommand(text: key.text),
        );
      },
    );
  }
}
```

**Tasks**:
- [ ] Integrate `xterm_flutter`
- [ ] Create terminal widget
- [ ] Configure terminal theme (Catppuccin)
- [ ] Handle keyboard input
- [ ] Scroll buffer management
- [ ] Custom fonts (JetBrains Mono)

### Step 4: Connection Management (3h)
```dart
// lib/features/connection/connection_provider.dart
class ConnectionState extends ChangeNotifier {
  bool _isConnected = false;
  String? _host;
  String? _error;

  bool get isConnected => _isConnected;
  String? get error => _error;

  Future<void> connect(String host, int port) async {
    try {
      _error = null;
      notifyListeners();

      await ComacodeBridge.connect(host, port);
      _isConnected = true;
      _host = host;
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
    } finally {
      notifyListeners();
    }
  }

  void disconnect() {
    _isConnected = false;
    _host = null;
    notifyListeners();
  }
}
```

**Tasks**:
- [ ] Implement connection state with Provider
- [ ] Add connection status indicator
- [ ] Handle connection errors
- [ ] Auto-reconnect logic
- [ ] Connection timeout handling

### Step 5: Discovery Screen (2h)
```dart
// lib/features/connection/discovery_page.dart
class DiscoveryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final connection = Provider.of<ConnectionState>(context);

    return Scaffold(
      appBar: AppBar(title: Text('Comacode')),
      body: Column(
        children: [
          if (connection.error != null)
            Container(
              padding: EdgeInsets.all(16),
              color: CatppuccinMocha.red.withOpacity(0.2),
              child: Text(connection.error!),
            ),
          Expanded(
            child: _buildHostList(context),
          ),
        ],
      ),
    );
  }
}
```

**Tasks**:
- [ ] Create discovery UI
- [ ] Show connection status
- [ ] Manual IP entry (fallback)
- [ ] Connection history
- [ ] Loading states

### Step 6: Terminal Controller (2h)
```dart
// lib/features/terminal/terminal_controller.dart
class TerminalController extends ChangeNotifier {
  final Terminal terminal = Terminal();

  void onEvent(TerminalEvent event) {
    switch (event) {
      case TerminalEventOutput(data: final data):
        terminal.write(data);
        break;
      case TerminalEventError(message: final message):
        terminal.write('Error: $message\n');
        break;
      case TerminalEventExit(code: final code):
        terminal.write('\n[Process exited with code $code]\n');
        break;
    }
  }
}
```

**Tasks**:
- [ ] Bridge xterm controller with Rust events
- [ ] Handle terminal resize
- [ ] Paste from clipboard
- [ ] Long-press for context menu
- [ ] Haptic feedback on type

## Todo List
- [ ] Create Flutter project
- [ ] Add dependencies (xterm_flutter, provider, FRB)
- [ ] Define Catppuccin theme
- [ ] Generate FFI bindings
- [ ] Build terminal widget
- [ ] Implement connection provider
- [ ] Create discovery screen
- [ ] Handle keyboard input
- [ ] Add error handling
- [ ] Test on iOS + Android

## Success Criteria
- Terminal renders text in Catppuccin theme
- Typing sends commands to Rust bridge
- Output streams from host to terminal
- Connection state managed properly
- App runs on iOS and Android
- Haptic feedback on keypress
- Smooth 60fps scrolling

## Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| xterm_flutter performance | Medium | High | Test with large output, optimize buffer |
| FFI crashes | Low | High | Add try-catch, crash reporting |
| Android keyboard issues | Medium | Medium | Test on multiple Android versions |
| iOS background restrictions | High | Medium | Handle app lifecycle, show warning |

## Security Considerations
- Validate all user input before sending
- Sanitize terminal output
- Warning for unencrypted connections (MVP only)
- No credential storage in MVP
- Certificate pinning (Phase 2)

## Related Code Files
- `/mobile/lib/main.dart` - App entry
- `/mobile/lib/features/terminal/` - Terminal UI
- `/mobile/lib/bridge/` - FFI wrapper
- `/crates/mobile_bridge/src/api.rs` - Rust FFI exports

## Next Steps
After UI works, proceed to [Phase 05: Network Protocol](./phase-05-network-protocol.md) for QUIC implementation.

## Resources
- [xterm_flutter examples](https://pub.dev/packages/xterm_flutter)
- [Flutter FFI guide](https://docs.flutter.dev/development/platform-integration/c-interop)
- [Provider pattern](https://pub.dev/packages/provider)
