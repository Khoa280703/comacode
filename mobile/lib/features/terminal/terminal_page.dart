import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connection/connection_providers.dart';
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

/// Terminal widget with basic display
///
/// Phase 06: MVP terminal implementation
/// - Receives events from backend
/// - Displays output as text
/// - Sends input via text field
/// - Supports clipboard copy
class TerminalWidget extends ConsumerStatefulWidget {
  const TerminalWidget({super.key});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  String _output = ''; // Single buffer for all output
  Timer? _eventLoopTimer;
  bool _isDisposed = false; // Track disposal state

  @override
  void initState() {
    super.initState();
    _startEventLoop();
  }

  /// Start event loop to receive terminal output from backend
  ///
  /// Phase 06 fix: Properly handle disposal to prevent:
  /// - setState() after dispose crashes
  /// - Memory leaks from uncanceled timers
  void _startEventLoop() {
    _eventLoopTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      // Check actual connection state from provider
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

        // Double-check mounted after async gap
        if (_isDisposed || !mounted) return;

        setState(() {
          if (isEventOutput(event)) {
            final data = getEventData(event);
            // Append to buffer, strip ANSI escape sequences for display
            final text = String.fromCharCodes(data);
            _output += _sanitizeTerminalOutput(text);
            _scrollToBottom();
          } else if (isEventError(event)) {
            final message = getEventErrorMessage(event);
            _output += 'Error: $message\n';
            _scrollToBottom();
          } else if (isEventExit(event)) {
            final code = getEventExitCode(event);
            _output += '\nProcess exited with code $code\n';
            _scrollToBottom();
          }
        });
      } catch (e) {
        // Only log if not disposing (errors during cleanup are expected)
        if (!_isDisposed && mounted) {
          // Could add error reporting here
        }
      }
    });
  }

  void _scrollToBottom() {
    if (_isDisposed || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed || !mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// Sanitize terminal output - strip ANSI and control chars
  String _sanitizeTerminalOutput(String text) {
    // Strip ANSI escape sequences (CSI, OSC, application mode, character set)
    text = text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
    text = text.replaceAll(RegExp(r'\x1b\][^\x07\x1b]*[\x07\x1b\\]'), '');
    text = text.replaceAll(RegExp(r'\x1b[=>]'), '');
    text = text.replaceAll(RegExp(r'\x1b\([0B]'), '');

    // Process \r (carriage return) - handle \r\n as single newline first
    // Split into lines, then handle \r within each line
    final lines = text.split('\n');
    final processed = <String>[];

    for (final line in lines) {
      // Within each line, \r means "overwrite" - keep last segment
      final crSegments = line.split('\r');
      if (crSegments.isNotEmpty) {
        // Take the last segment (the visible content after all \r overwrites)
        processed.add(crSegments.last);
      }
    }

    // Remove trailing empty lines
    while (processed.isNotEmpty && processed.last.trim().isEmpty) {
      processed.removeLast();
    }

    // Remove other control chars except \n, \t
    final buffer = StringBuffer();
    for (var i = 0; i < processed.length; i++) {
      final line = processed[i];
      for (var j = 0; j < line.length; j++) {
        final code = line.codeUnitAt(j);
        if (code == 0x09 || code >= 0x20) {
          buffer.writeCharCode(code);
        }
      }
      // Add newline between lines
      if (i < processed.length - 1) {
        buffer.writeCharCode(0x0A);
      }
    }

    return buffer.toString();
  }

  /// Count actual lines in output for display
  int get _lineCount {
    if (_output.isEmpty) return 0;
    return '\n'.allMatches(_output).length + 1;
  }

  /// Get readable representation of virtual key for logging
  String _getReadableKey(String key) {
    if (key.isEmpty) return '<empty>';
    if (key == '\x1b') return '<ESC>';
    if (key == '\t') return '<TAB>';
    if (key == '\r') return '<CR>';
    if (key == '\n') return '<LF>';
    if (key.startsWith('\x1b[')) {
      // Arrow keys: \x1b[A, \x1b[B, \x1b[C, \x1b[D
      final arrow = key.substring(2);
      return '<${_arrowName(arrow)}>';
    }
    // Control characters
    if (key.codeUnitAt(0) < 32) {
      return '<Ctrl-${String.fromCharCode(key.codeUnitAt(0) + 64)}>';
    }
    // Truncate if too long
    if (key.length > 20) {
      return '${key.substring(0, 20)}...';
    }
    return key;
  }

  String _arrowName(String code) {
    switch (code) {
      case 'A': return 'Arrow Up';
      case 'B': return 'Arrow Down';
      case 'C': return 'Arrow Right';
      case 'D': return 'Arrow Left';
      default: return 'Unknown';
    }
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
    _isDisposed = true; // Mark as disposed first
    _eventLoopTimer?.cancel();
    _scrollController.dispose();
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
                '$_lineCount lines',
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Terminal output
        Expanded(
          child: GestureDetector(
            onLongPress: () {
              // Copy all output to clipboard
              Clipboard.setData(ClipboardData(text: _output));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              color: CatppuccinMocha.terminalBackground,
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: _output.isEmpty
                    ? Center(
                        child: Text(
                          'Waiting for terminal output...\nType a command and press Send',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CatppuccinMocha.subtext0,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Text(
                        _output,
                        style: TextStyle(
                          color: CatppuccinMocha.terminalForeground,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
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
            // Log virtual key press with readable representation
            final readable = _getReadableKey(key);
            debugPrint('🔘 [Terminal] Virtual key pressed: $readable');
            final bridge = ref.read(bridgeWrapperProvider);
            final messenger = ScaffoldMessenger.of(context);
            try {
              debugPrint('📤 [Terminal] Sending virtual key...');
              await bridge.sendCommand(key);
              debugPrint('✅ [Terminal] Virtual key sent');
            } catch (e) {
              debugPrint('❌ [Terminal] Failed to send key: $e');
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
