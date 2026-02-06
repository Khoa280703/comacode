import 'package:xterm/xterm.dart';
import 'view_mode.dart';

/// Vibe session state management
class VibeSessionState {
  final bool isConnected;
  final Terminal terminal;
  final bool isSending;
  final String? error;
  final ViewMode viewMode;

  VibeSessionState({
    this.isConnected = false,
    Terminal? terminal,
    this.isSending = false,
    this.error,
    this.viewMode = ViewMode.terminal,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  VibeSessionState copyWith({
    bool? isConnected,
    Terminal? terminal,
    bool? isSending,
    String? error,
    ViewMode? viewMode,
  }) {
    return VibeSessionState(
      isConnected: isConnected ?? this.isConnected,
      terminal: terminal ?? this.terminal,
      isSending: isSending ?? this.isSending,
      error: error,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}
