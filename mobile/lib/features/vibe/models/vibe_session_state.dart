import 'package:xterm/xterm.dart';

/// Vibe session state management
class VibeSessionState {
  final bool isConnected;
  final bool isOutputModeRaw;
  final Terminal terminal;
  final bool isSending;
  final String? error;

  VibeSessionState({
    this.isConnected = false,
    this.isOutputModeRaw = true,
    Terminal? terminal,
    this.isSending = false,
    this.error,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  VibeSessionState copyWith({
    bool? isConnected,
    bool? isOutputModeRaw,
    Terminal? terminal,
    bool? isSending,
    String? error,
  }) {
    return VibeSessionState(
      isConnected: isConnected ?? this.isConnected,
      isOutputModeRaw: isOutputModeRaw ?? this.isOutputModeRaw,
      terminal: terminal ?? this.terminal,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}
