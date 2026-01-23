import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../connection/connection_providers.dart';
import '../vfs/vfs_page.dart';
import '../../bridge/bridge_wrapper.dart';
import '../../bridge/ffi_helpers.dart';
import '../../core/theme.dart';
import 'virtual_key_bar.dart';

/// Terminal page with basic terminal UI
///
/// Phase 06: Full terminal implementation
/// - Basic terminal display with simple text rendering
/// - Riverpod for state management
/// - PTY resize on screen rotation
/// - Clipboard support
///
/// Note: Full xterm.dart integration deferred due to API complexity
/// Using simple terminal output for MVP
class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          connectionState.isConnected
              ? 'Terminal - ${_getHostDisplayName(connectionState)}'
              : 'Terminal',
        ),
        backgroundColor: CatppuccinMocha.mantle,
        actions: [
          _ConnectionStatusIndicator(state: connectionState),
          if (connectionState.isConnected)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'File Browser',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VfsPage(),
                  ),
                );
              },
            ),
          if (connectionState.isConnected)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'disconnect') {
                  await ref.read(connectionStateProvider.notifier).disconnect();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'disconnect',
                  child: ListTile(
                    leading: Icon(Icons.close),
                    title: Text('Disconnect'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: connectionState.isConnected
          ? const TerminalWidget()
          : _buildDisconnected(context, connectionState),
    );
  }

  String _getHostDisplayName(ConnectionModel state) {
    // Try to get from currentHost
    if (state.currentHost != null) {
      return 'Connected';
    }
    return 'Connected';
  }

  Widget _buildDisconnected(BuildContext context, ConnectionModel state) {
    return Center(
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              state.errorMessage ?? 'Please scan QR code to connect',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CatppuccinMocha.mauve,
              foregroundColor: CatppuccinMocha.crust,
            ),
          ),
        ],
      ),
    );
  }
}

/// Connection status indicator widget
class _ConnectionStatusIndicator extends StatelessWidget {
  final ConnectionModel state;

  const _ConnectionStatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    Color getColor() {
      switch (state.status) {
        case ConnectionStatus.connected:
          return CatppuccinMocha.green;
        case ConnectionStatus.connecting:
          return CatppuccinMocha.yellow;
        case ConnectionStatus.error:
          return CatppuccinMocha.red;
        case ConnectionStatus.disconnected:
          return CatppuccinMocha.surface1;
      }
    }

    String getText() {
      switch (state.status) {
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

/// Terminal widget with xterm emulator
///
/// Phase 06 Fix: Proper terminal emulation with xterm
/// - Full VT100/ANSI escape code support
/// - Proper cursor positioning and colors
/// - Scrollback buffer
/// - Real terminal behavior
class TerminalWidget extends ConsumerStatefulWidget {
  const TerminalWidget({super.key});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget> {
  late final Terminal _terminal;
  final TextEditingController _inputController = TextEditingController();
  Timer? _eventLoopTimer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // Create xterm terminal instance
    _terminal = Terminal(
      maxLines: 10000, // Scrollback buffer size
    );
    _startEventLoop();
    
    // Initialize terminal after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTerminal();
    });
  }
  
  /// Initialize terminal - send size and trigger prompt
  Future<void> _initializeTerminal() async {
    if (_isDisposed || !mounted) return;
    
    try {
      final bridge = ref.read(bridgeWrapperProvider);
      
      // Calculate terminal size based on screen
      // Typical mobile terminal: ~30 rows x 80 cols for portrait
      // Adjust based on font size (14px) and screen height
      final size = MediaQuery.of(context).size;
      final rows = ((size.height - 200) / 18).floor(); // ~18px per line with 14px font
      final cols = ((size.width - 16) / 8.4).floor();  // ~8.4px per char with 14px font
      
      debugPrint('🖥️  [Terminal] Initializing with size: ${rows}x$cols');
      
      // FIX: Send resize to backend PTY
      await bridge.resizePty(rows: rows, cols: cols);
      
      // FIX RACE CONDITION: Wait longer for network + PTY processing
      // Network RTT (~10-50ms) + PTY creation (~50-100ms) + Shell init (~100-200ms)
      // Total: ~300ms to be safe
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Send newline to trigger prompt display
      // This will create the PTY session with correct size from pending_resize
      await bridge.sendCommand('\n');
      
      // Wait for prompt to appear
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Send clear screen to refresh display (Ctrl+L)
      await bridge.sendCommand('\x0c');
      
      debugPrint('✅ [Terminal] Initialized successfully');
    } catch (e) {
      debugPrint('❌ [Terminal] Failed to initialize: $e');
    }
  }

  /// Start event loop to receive terminal output from backend
  ///
  /// Phase 06 fix: Use xterm terminal emulator for proper ANSI handling
  void _startEventLoop() {
    _eventLoopTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      final connectionState = ref.read(connectionStateProvider);
      if (_isDisposed || !connectionState.isConnected || !mounted) {
        if (!connectionState.isConnected) {
          timer.cancel();
        }
        return;
      }

      try {
        final bridge = ref.read(bridgeWrapperProvider);
        final event = await bridge.receiveEvent();

        if (_isDisposed || !mounted) return;

        if (isEventOutput(event)) {
          final data = getEventData(event);
          if (data.isNotEmpty) {
            // FIX: Use proper UTF-8 decoder for Vietnamese/emoji support
            // utf8.decode() handles multi-byte chars correctly
            // allowMalformed: true prevents crashes on invalid UTF-8
            try {
              final text = utf8.decode(data, allowMalformed: true);
              _terminal.write(text);
            } catch (e) {
              // Fallback: Try Latin-1 if UTF-8 fails completely
              debugPrint('⚠️  [Terminal] UTF-8 decode failed: $e');
              final text = String.fromCharCodes(data);
              _terminal.write(text);
            }
          }
        } else if (isEventError(event)) {
          final message = getEventErrorMessage(event);
          _terminal.write('\x1b[31mError: $message\x1b[0m\r\n');
        } else if (isEventExit(event)) {
          final code = getEventExitCode(event);
          _terminal.write('\r\n\x1b[33mProcess exited with code $code\x1b[0m\r\n');
        }
      } catch (e) {
        if (!_isDisposed && mounted) {
          // Could add error reporting here
        }
      }
    });
  }


  /// Send input to terminal
  Future<void> _sendInput(BuildContext context) async {
    final text = _inputController.text;
    if (text.isEmpty) return;

    final bridge = ref.read(bridgeWrapperProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Debug logging
      debugPrint('🟢 [Terminal] Sending command: "$text"');
      await bridge.sendCommand('$text\r');
      debugPrint('✅ [Terminal] Command sent successfully');
      _inputController.clear();
    } catch (e) {
      debugPrint('❌ [Terminal] Failed to send command: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to send command: $e'),
            backgroundColor: CatppuccinMocha.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _eventLoopTimer?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Connection status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: CatppuccinMocha.surface0,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: CatppuccinMocha.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Connected',
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                'Terminal Ready',
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Terminal display with xterm
        Expanded(
          child: Container(
            color: CatppuccinMocha.terminalBackground,
            child: TerminalView(
              _terminal,
              textStyle: TerminalStyle(
                fontSize: 14,
                fontFamily: 'Courier',
              ),
              theme: TerminalTheme(
                cursor: CatppuccinMocha.green,
                selection: CatppuccinMocha.surface1,
                foreground: CatppuccinMocha.terminalForeground,
                background: CatppuccinMocha.terminalBackground,
                black: CatppuccinMocha.surface0,
                red: CatppuccinMocha.red,
                green: CatppuccinMocha.green,
                yellow: CatppuccinMocha.yellow,
                blue: CatppuccinMocha.blue,
                magenta: CatppuccinMocha.mauve,
                cyan: CatppuccinMocha.teal,
                white: CatppuccinMocha.text,
                brightBlack: CatppuccinMocha.surface1,
                brightRed: CatppuccinMocha.red,
                brightGreen: CatppuccinMocha.green,
                brightYellow: CatppuccinMocha.yellow,
                brightBlue: CatppuccinMocha.blue,
                brightMagenta: CatppuccinMocha.mauve,
                brightCyan: CatppuccinMocha.teal,
                brightWhite: CatppuccinMocha.text,
                searchHitBackground: CatppuccinMocha.yellow,
                searchHitBackgroundCurrent: CatppuccinMocha.peach,
                searchHitForeground: CatppuccinMocha.base,
              ),
            ),
          ),
        ),

        // Input field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: CatppuccinMocha.surface0,
            border: Border(
              top: BorderSide(color: CatppuccinMocha.surface1, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                '\$ ',
                style: TextStyle(
                  color: CatppuccinMocha.green,
                  fontFamily: 'monospace',
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: TextStyle(
                    color: CatppuccinMocha.text,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter command...',
                    hintStyle: TextStyle(color: Color(0xFF6C7086)),
                  ),
                  onChanged: (value) {
                    debugPrint('⌨️  [Terminal] Key pressed: "$value"');
                  },
                  onSubmitted: (value) {
                    debugPrint('⏎ [Terminal] Enter pressed: "$value"');
                    _sendInput(context);
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, color: CatppuccinMocha.mauve),
                onPressed: () => _sendInput(context),
              ),
            ],
          ),
        ),

        // Virtual keyboard
        VirtualKeyBar(
          onKeyPressed: (key) async {
            final bridge = ref.read(bridgeWrapperProvider);
            final messenger = ScaffoldMessenger.of(context);
            try {
              // Send virtual key to backend (backend will echo it back)
              await bridge.sendCommand(key);
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to send key: $e'),
                    backgroundColor: CatppuccinMocha.red,
                  ),
                );
              }
            }
          },
          onToggleKeyboard: () {
            // Toggle virtual keyboard visibility (optional enhancement)
          },
        ),
      ],
    );
  }
}
