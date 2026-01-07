import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../connection/connection_provider.dart';
import 'virtual_key_bar.dart';

/// Terminal page with virtual key bar
///
/// Phase 04: Mobile App
/// Displays terminal output with virtual keyboard for special keys
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isKeyboardVisible = true;
  bool _isWakelockEnabled = true;

  @override
  void initState() {
    super.initState();
    // Listen to connection state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connectionProvider = context.read<ConnectionProvider>();
      if (!connectionProvider.isConnected) {
        _navigateToHome();
      }
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _commandFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _submitCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    final connectionProvider = context.read<ConnectionProvider>();
    connectionProvider.sendCommand(command);

    _commandController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleVirtualKey(String keySequence) {
    final connectionProvider = context.read<ConnectionProvider>();

    if (keySequence.isEmpty) {
      // CTRL was pressed (handled by UI state)
      return;
    }

    // Send special key sequence
    connectionProvider.sendCommand(keySequence);
  }

  void _toggleKeyboard() {
    setState(() {
      _isKeyboardVisible = !_isKeyboardVisible;
      if (_isKeyboardVisible) {
        _commandFocus.requestFocus();
      } else {
        _commandFocus.unfocus();
      }
    });
  }

  void _toggleWakelock() {
    // This is just UI state - actual wakelock is managed by ConnectionProvider
    setState(() {
      _isWakelockEnabled = !_isWakelockEnabled;
    });
    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isWakelockEnabled ? 'Screen lock enabled' : 'Screen lock disabled',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E), // Catppuccin base
      appBar: AppBar(
        title: Consumer<ConnectionProvider>(
          builder: (context, connection, _) {
            return Text(connection.hostDisplayName ?? 'Terminal');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear terminal',
            onPressed: () {
              context.read<ConnectionProvider>().clearTerminal();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'disconnect') {
                context.read<ConnectionProvider>().disconnect();
                _navigateToHome();
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
        ],
      ),
      body: Column(
        children: [
          // Terminal output area
          Expanded(
            child: Consumer<ConnectionProvider>(
              builder: (context, connection, _) {
                if (connection.terminalOutput.isEmpty) {
                  return const Center(
                    child: Text(
                      'Connecting...',
                      style: TextStyle(
                        color: Color(0xFF6C7086),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: connection.terminalOutput.length,
                  itemBuilder: (context, index) {
                    final line = connection.terminalOutput[index];
                    return _buildTerminalLine(line, theme);
                  },
                );
              },
            ),
          ),

          // Command input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '\$ ',
                  style: TextStyle(
                    color: Color(0xFFA6E3A1), // Green
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    focusNode: _commandFocus,
                    decoration: const InputDecoration(
                      hintText: 'Enter command...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: Color(0xFF6C7086),
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFFCDD6F4), // Text
                      fontFamily: 'monospace',
                    ),
                    onSubmitted: (_) => _submitCommand(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: theme.colorScheme.primary,
                  onPressed: _submitCommand,
                ),
              ],
            ),
          ),

          // Virtual key bar
          VirtualKeyBar(
            onKeyPressed: _handleVirtualKey,
            onToggleKeyboard: _toggleKeyboard,
            onToggleWakelock: _toggleWakelock,
            isKeyboardVisible: _isKeyboardVisible,
            isWakelockEnabled: _isWakelockEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalLine(String line, ThemeData theme) {
    // Simple syntax highlighting (could be enhanced)
    Color textColor = const Color(0xFFCDD6F4); // Default text

    if (line.startsWith('\$ ') || line.startsWith('% ')) {
      textColor = const Color(0xFFA6E3A1); // Green for prompt
    } else if (line.contains('Connected to')) {
      textColor = const Color(0xFF89B4FA); // Blue for info
    } else if (line.contains('Error') || line.contains('Failed')) {
      textColor = const Color(0xFFF38BA8); // Red for errors
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        line,
        style: TextStyle(
          color: textColor,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
    );
  }
}
