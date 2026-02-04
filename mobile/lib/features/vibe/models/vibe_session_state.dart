import 'package:xterm/xterm.dart';

/// Vibe session state management
class VibeSessionState {
  final bool isConnected;
  final Terminal terminal;
  final bool isSending;
  final String? error;

  VibeSessionState({
    this.isConnected = false,
    Terminal? terminal,
    this.isSending = false,
    this.error,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  VibeSessionState copyWith({
    bool? isConnected,
    Terminal? terminal,
    bool? isSending,
    String? error,
  }) {
    return VibeSessionState(
      isConnected: isConnected ?? this.isConnected,
      terminal: terminal ?? this.terminal,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}
