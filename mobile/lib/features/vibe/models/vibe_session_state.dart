import 'package:xterm/xterm.dart';
import 'view_mode.dart';

/// Vibe session state management
class VibeSessionState {
  final bool isConnected;
  final Terminal terminal;
  final bool isSending;
  final String? error;
  final ViewMode viewMode;

  /// Currently opened file path (null = no file open)
  final String? openedFilePath;
  /// Currently opened file name (for display)
  final String? openedFileName;
  /// Last browsed path in file explorer (for state persistence)
  final String? lastBrowsedPath;

  VibeSessionState({
    this.isConnected = false,
    Terminal? terminal,
    this.isSending = false,
    this.error,
    this.viewMode = ViewMode.terminal,
    this.openedFilePath,
    this.openedFileName,
    this.lastBrowsedPath,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  VibeSessionState copyWith({
    bool? isConnected,
    Terminal? terminal,
    bool? isSending,
    String? error,
    ViewMode? viewMode,
    String? openedFilePath,
    String? openedFileName,
    String? lastBrowsedPath,
    bool clearOpenedFile = false,
  }) {
    return VibeSessionState(
      isConnected: isConnected ?? this.isConnected,
      terminal: terminal ?? this.terminal,
      isSending: isSending ?? this.isSending,
      error: error,
      viewMode: viewMode ?? this.viewMode,
      openedFilePath: clearOpenedFile ? null : (openedFilePath ?? this.openedFilePath),
      openedFileName: clearOpenedFile ? null : (openedFileName ?? this.openedFileName),
      lastBrowsedPath: lastBrowsedPath ?? this.lastBrowsedPath,
    );
  }

  /// Check if a file is currently open
  bool get hasOpenedFile => openedFilePath != null;
}
