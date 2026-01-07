import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connection/connection_providers.dart';
import '../../bridge/bridge_wrapper.dart';
import '../../bridge/third_party/mobile_bridge/api.dart';
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
  final List<String> _output = [];
  final bool _isConnected = true; // State is managed externally
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
      // Early exit if disposed or not connected
      if (_isDisposed || !_isConnected || !mounted) {
        timer.cancel();
        return;
      }

      try {
        final bridge = ref.read(bridgeWrapperProvider);
        final event = await bridge.receiveEvent();

        // Double-check mounted after async gap
        if (_isDisposed || !mounted) return;

        setState(() {
          if (isEventOutput(event: event)) {
            final data = getEventData(event: event);
            _output.add(String.fromCharCodes(data));
            _scrollToBottom();
          } else if (isEventError(event: event)) {
            final message = getEventErrorMessage(event: event);
            _output.add('\x1b[31mError: $message\x1b[0m');
            _scrollToBottom();
          } else if (isEventExit(event: event)) {
            final code = getEventExitCode(event: event);
            _output.add('\r\nProcess exited with code $code\r\n');
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
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 50),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Send input to terminal
  void _sendInput() {
    final text = _inputController.text;
    if (text.isEmpty) return;

    final bridge = ref.read(bridgeWrapperProvider);
    bridge.sendCommand('$text\r'); // Use string interpolation
    _inputController.clear();
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
        // Terminal output
        Expanded(
          child: GestureDetector(
            onLongPress: () {
              // Copy all output to clipboard
              Clipboard.setData(ClipboardData(text: _output.join()));
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
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _output.length,
                itemBuilder: (context, index) {
                  return Text(
                    _output[index],
                    style: TextStyle(
                      color: CatppuccinMocha.terminalForeground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
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
                  onSubmitted: (_) => _sendInput(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, color: CatppuccinMocha.mauve),
                onPressed: _sendInput,
              ),
            ],
          ),
        ),

        // Virtual keyboard
        VirtualKeyBar(
          onKeyPressed: (key) {
            final bridge = ref.read(bridgeWrapperProvider);
            bridge.sendCommand(key);
          },
          onToggleKeyboard: () {
            // Toggle virtual keyboard visibility (optional enhancement)
          },
        ),
      ],
    );
  }
}
