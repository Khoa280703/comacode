import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../bridge/bridge_wrapper.dart';
import '../../bridge/api.dart' as frb_api;
import 'models/output_buffer.dart';
import 'models/special_key.dart';
import 'models/vibe_session_state.dart';
import 'models/view_mode.dart';

/// Vibe session state provider
///
/// NOTE: Removed autoDispose to keep event loop alive during navigation
/// With autoDispose, navigating back kills the event loop → commands fail silently
/// Trade-off: Provider stays alive in memory, but ensures PTY connection stability
final vibeSessionProvider =
    StateNotifierProvider<VibeSessionNotifier, VibeSessionState>((ref) {
  return VibeSessionNotifier(ref.read(bridgeWrapperProvider));
});

/// Vibe session notifier
class VibeSessionNotifier extends StateNotifier<VibeSessionState> {
  final BridgeWrapper _bridge;

  VibeSessionNotifier(this._bridge)
      : super(VibeSessionState()) {
    _startEventLoop();
  }

  Timer? _eventLoopTimer;
  Timer? _healthCheckTimer;
  bool _isDisposed = false;
  int _eventLoopCount = 0;
  String? _currentSessionId;
  bool _isEventLoopHealthy = false;

  /// Callback for terminal output (used by storage to persist history)
  /// Map from sessionId to callback - allows per-session storage
  final Map<String, void Function(String)> _outputCallbacks = {};

  /// Register output callback for a session
  void registerOutputCallback(String sessionId, void Function(String) callback) {
    _outputCallbacks[sessionId] = callback;
  }

  /// Unregister output callback for a session
  void unregisterOutputCallback(String sessionId) {
    _outputCallbacks.remove(sessionId);
  }

  /// Per-session terminal cache — keeps Terminal alive across session switches
  final Map<String, Terminal> _terminalCache = {};
  /// Per-session output buffer cache
  final Map<String, OutputBuffer> _bufferCache = {};
  /// Per-session last-sent terminal size [cols, rows] — persists across widget rebuilds
  final Map<String, List<int>> _sizeCache = {};

  /// Persist last sent terminal size for session (called by widget after resizePty)
  void updateLastSentSize(String sessionId, int cols, int rows) {
    _sizeCache[sessionId] = [cols, rows];
  }

  /// Read last sent terminal size for session (used on widget re-mount to skip redundant resize)
  List<int>? getLastSentSize(String sessionId) => _sizeCache[sessionId];

  /// Get or create Terminal for a session
  Terminal _getOrCreateTerminal(String sessionId) {
    return _terminalCache.putIfAbsent(sessionId, () => Terminal(maxLines: 10000));
  }

  /// Public accessor to get terminal for a specific session (used by storage to load history)
  Terminal getTerminalForSession(String sessionId) {
    return _getOrCreateTerminal(sessionId);
  }

  /// Get or create OutputBuffer for a session
  OutputBuffer _getOrCreateBuffer(String sessionId) {
    return _bufferCache.putIfAbsent(sessionId, () => OutputBuffer());
  }

  /// Active output buffer (points to current session's buffer)
  OutputBuffer get _outputBuffer => _getOrCreateBuffer(_currentSessionId ?? '');

  /// Attach/switch to a session (restart event loop if needed)
  Future<void> attachSession(String sessionId) async {
    debugPrint('🔄 [VibeSession] Attaching to session: $sessionId (current: $_currentSessionId)');

    final isDifferentSession = _currentSessionId != sessionId;
    final isEventLoopDead = _eventLoopTimer == null;

    if (isDifferentSession) {
      debugPrint('🔄 [VibeSession] Session changed, restarting event loop');

      // Stop old event loop
      _isDisposed = true;
      _eventLoopTimer?.cancel();
      _eventLoopTimer = null;

      // Switch to cached terminal for new session (no clear!)
      _currentSessionId = sessionId;
      final terminal = _getOrCreateTerminal(sessionId);
      state = state.copyWith(terminal: terminal);

      _isDisposed = false;
      _eventLoopCount = 0;

      debugPrint('[VibeSession] Starting new event loop for $sessionId');
      _startEventLoop();
    } else if (isEventLoopDead) {
      debugPrint('[VibeSession] Event loop was dead, restarting for $sessionId');
      _isDisposed = false;
      _startEventLoop();
    } else {
      debugPrint('[VibeSession] Event loop already running for $sessionId');
    }
  }

  /// Check if currently attached to a specific session (event loop running for it)
  bool isAttachedTo(String sessionId) => _currentSessionId == sessionId;

  /// Check if session was previously created (terminal cached) — survives session switches
  bool hasSession(String sessionId) => _terminalCache.containsKey(sessionId);

  /// Send prompt text to backend
  Future<void> sendPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;

    state = state.copyWith(isSending: true, error: null);

    try {
      // FIX: Add \r (Enter key) to execute command
      // Without \r, shell just adds text to current line without executing
      await _bridge.sendCommand('$prompt\r').timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Send command timeout');
        },
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to send prompt: $e');
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  /// Send special key to backend
  Future<void> sendSpecialKey(SpecialKey key) async {
    try {
      await _bridge.sendCommand(key.sequence);
    } catch (e) {
      state = state.copyWith(error: 'Failed to send key: $e');
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Set view mode (Terminal or Files)
  void setViewMode(ViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  /// Toggle between terminal and files mode
  void toggleViewMode() {
    final newMode = state.viewMode == ViewMode.terminal
        ? ViewMode.files
        : ViewMode.terminal;
    setViewMode(newMode);
  }

  /// Open a file in the file viewer
  void openFile(String path, String name) {
    state = state.copyWith(
      openedFilePath: path,
      openedFileName: name,
    );
  }

  /// Close the currently opened file
  void closeFile() {
    state = state.copyWith(clearOpenedFile: true);
  }

  /// Update last browsed path for file explorer state persistence
  void updateLastBrowsedPath(String path) {
    state = state.copyWith(lastBrowsedPath: path);
  }

  /// Start event loop to receive PTY output
  void _startEventLoop() {
    // Cancel old health check timer if exists
    _healthCheckTimer?.cancel();

    debugPrint('🔄 [EventLoop] STARTING event loop for session: $_currentSessionId');

    _eventLoopTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) async {
        if (_isDisposed) {
          timer.cancel();
          debugPrint('🛑 [EventLoop] STOPPED - disposed');
          return;
        }

        try {
          // DEBUG: Log before receiveEvent() call
          if (_eventLoopCount < 5) {
            debugPrint('📥 [EventLoop] Calling receiveEvent() #${_eventLoopCount + 1}');
          }

          final event = await _bridge.receiveEvent();

          if (_isDisposed) return;

          // Mark event loop as healthy when we receive events
          _isEventLoopHealthy = true;

          // Debug: log event type (heavily throttled - only every 1000 events)
          _eventLoopCount++;
          if (_eventLoopCount % 1000 == 1) {
            debugPrint('[EventLoop] Processed $_eventLoopCount events');
          }

          // DEBUG: Log event type for first 10 events
          if (_eventLoopCount <= 10) {
            final isOutput = isEventOutput(event);
            final isError = isEventError(event);
            final isExit = isEventExit(event);
            debugPrint('📦 [EventLoop] Event #$_eventLoopCount: Output=$isOutput, Error=$isError, Exit=$isExit');
          }

          if (isEventOutput(event)) {
            final data = getEventData(event);

            // DEBUG: ALWAYS log output events for first 20 events
            if (_eventLoopCount <= 20) {
              debugPrint('📤 [EventLoop] Output event #$_eventLoopCount: ${data.length} bytes');
              if (data.isNotEmpty) {
                final preview = data.take(50).toList();
                debugPrint('   Raw bytes: $preview');
              }
            }

            // Only log non-zero output to reduce spam
            if (data.isNotEmpty && data.length % 1000 == 0 && kDebugMode) {
              debugPrint('  → Output data size: ${data.length} bytes');
            }
            if (data.isNotEmpty) {
              try {
                // FIX: Use proper UTF-8 decoder for Vietnamese/emoji support
                // utf8.decode() handles multi-byte chars correctly (à, 你, 🚀)
                // allowMalformed: true prevents crashes on invalid UTF-8
                final text = utf8.decode(data, allowMalformed: true);

                // DEBUG: Log decoded text for first 10 non-empty outputs
                if (_eventLoopCount <= 10 && text.isNotEmpty) {
                  final preview = text.length > 100 ? text.substring(0, 100) : text;
                  debugPrint('📝 [EventLoop] Decoded text: "$preview"');
                  debugPrint('✍️  [EventLoop] Writing to terminal...');
                }

                // Add to output buffer (limits memory growth)
                _outputBuffer.add(text);

                // Write to terminal for display
                state.terminal.write(text);

                // Notify storage to persist output (per-session callback)
                if (_currentSessionId != null) {
                  _outputCallbacks[_currentSessionId]?.call(text);
                }

                // DEBUG: Confirm write for first 10 events
                if (_eventLoopCount <= 10 && text.isNotEmpty) {
                  debugPrint('✅ [EventLoop] Terminal write complete');
                }

                // Log buffer stats periodically for monitoring
                if (_outputBuffer.length % 1000 == 0) {
                  final stats = _outputBuffer.stats;
                  if (stats['isFull'] == true) {
                    // Buffer at capacity - oldest lines being dropped
                    debugPrint('Output buffer at capacity: ${stats['lines']} lines');
                  }
                }
              } catch (e) {
                // Fallback: Try Latin-1 if UTF-8 fails completely
                debugPrint('[EventLoop] UTF-8 decode failed: $e');
                final text = String.fromCharCodes(data);
                _outputBuffer.add(text);
                state.terminal.write(text);
              }
            } else {
              // DEBUG: Log empty output events
              if (_eventLoopCount <= 20) {
                debugPrint('⚠️  [EventLoop] Empty output event #$_eventLoopCount');
              }
            }
          } else if (isEventError(event)) {
            final message = getEventErrorMessage(event);
            debugPrint('❌ [EventLoop] Error event: $message');
            final errorText = '\x1b[31mError: $message\x1b[0m\r\n';
            _outputBuffer.add(errorText);
            state.terminal.write(errorText);
          } else if (isEventExit(event)) {
            final code = getEventExitCode(event);
            debugPrint('🚪 [EventLoop] Exit event: code=$code');
            final exitText = '\r\n\x1b[33mProcess exited with code $code\x1b[0m\r\n';
            _outputBuffer.add(exitText);
            state.terminal.write(exitText);
          }
        } catch (e, stackTrace) {
          // Log for debugging - event loop errors
          debugPrint('💥 [EventLoop] ERROR: $e');
          if (_eventLoopCount < 5) {
            debugPrint('   Stack trace: $stackTrace');
          }
        }
      },
    );

    // Start health check timer - monitors if event loop is receiving events
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!_isEventLoopHealthy && !_isDisposed && _eventLoopTimer != null) {
          debugPrint('[EventLoop] No events for 5 seconds - PTY may be dead or disconnected');
          // TODO: Could trigger reconnection or show user-facing error here
        }
        _isEventLoopHealthy = false; // Reset flag for next check
      },
    );
  }

  /// Get buffered output (for search/export features)
  String getBufferedOutput() {
    return _outputBuffer.toString();
  }

  /// Get buffer statistics
  Map<String, dynamic> getBufferStats() {
    return _outputBuffer.stats;
  }

  /// Clear output buffer and terminal
  void clearOutput() {
    _outputBuffer.clear();
    state.terminal.eraseDisplay();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _eventLoopTimer?.cancel();
    _healthCheckTimer?.cancel();
    _terminalCache.clear();
    _bufferCache.clear();
    _sizeCache.clear();
    super.dispose();
  }
}

// Helper functions using FRB-generated API
bool isEventOutput(dynamic event) => frb_api.isEventOutput(event: event);
List<int> getEventData(dynamic event) => frb_api.getEventData(event: event);
bool isEventError(dynamic event) => frb_api.isEventError(event: event);
String getEventErrorMessage(dynamic event) => frb_api.getEventErrorMessage(event: event);
bool isEventExit(dynamic event) => frb_api.isEventExit(event: event);
int getEventExitCode(dynamic event) => frb_api.getEventExitCode(event: event);
