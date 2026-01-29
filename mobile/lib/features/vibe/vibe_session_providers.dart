import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_wrapper.dart';
import '../../bridge/api.dart' as frb_api;
import 'models/output_buffer.dart';
import 'models/special_key.dart';
import 'models/vibe_session_state.dart';

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
    // Initialize terminal
    _startEventLoop();
  }

  Timer? _eventLoopTimer;
  Timer? _healthCheckTimer;
  bool _isDisposed = false;
  int _eventLoopCount = 0;
  String? _currentSessionId;
  bool _isEventLoopHealthy = false;

  /// Attach/switch to a session (restart event loop if needed)
  ///
  /// Called when entering VibeSessionPage to ensure fresh event loop
  /// for the current session. Prevents race condition where old event loop
  /// listens to wrong PTY after session switch.
  Future<void> attachSession(String sessionId) async {
    debugPrint('🔄 [VibeSession] Attaching to session: $sessionId (current: $_currentSessionId)');

    // CRITICAL: Don't early return based on session ID match
    // The event loop might be dead even if session ID matches
    // Instead, check if event loop is actually running

    final isDifferentSession = _currentSessionId != sessionId;
    final isEventLoopDead = _eventLoopTimer == null;

    if (isDifferentSession) {
      debugPrint('🔄 [VibeSession] Session changed, restarting event loop');

      // Stop old event loop
      _isDisposed = true;
      _eventLoopTimer?.cancel();
      _eventLoopTimer = null;

      // CRITICAL FIX: Don't clear terminal on re-entry to same session
      // Only clear when switching to a different session
      if (_currentSessionId != null) {
        _outputBuffer.clear();
        state.terminal.eraseDisplay();
      }

      // Update session ID and restart
      _currentSessionId = sessionId;
      _isDisposed = false;
      _eventLoopCount = 0;

      debugPrint('✅ [VibeSession] Starting new event loop for $sessionId');
      _startEventLoop();
    } else if (isEventLoopDead) {
      // Same session but event loop is dead - restart it
      debugPrint('🔄 [VibeSession] Event loop was dead, restarting for $sessionId');
      _isDisposed = false;
      _startEventLoop();
    } else {
      // Event loop already running for this session
      debugPrint('✅ [VibeSession] Event loop already running for $sessionId');
    }
  }

  /// Check if currently attached to a specific session
  bool isAttachedTo(String sessionId) => _currentSessionId == sessionId;

  /// Output buffer to prevent memory issues with large output
  final OutputBuffer _outputBuffer = OutputBuffer();

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

  /// Toggle between Raw and Parsed mode
  void toggleOutputMode() {
    state = state.copyWith(isOutputModeRaw: !state.isOutputModeRaw);
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Start event loop to receive PTY output
  void _startEventLoop() {
    // Cancel old health check timer if exists
    _healthCheckTimer?.cancel();

    _eventLoopTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) async {
        if (_isDisposed) {
          timer.cancel();
          return;
        }

        try {
          final event = await _bridge.receiveEvent();

          if (_isDisposed) return;

          // Mark event loop as healthy when we receive events
          _isEventLoopHealthy = true;

          // Debug: log event type (throttled)
          _eventLoopCount++;
          if (_eventLoopCount % 50 == 1) {
            debugPrint('📥 [EventLoop] Event #$_eventLoopCount: ${event.runtimeType}');
          }

          // Debug: check event type
          if (_eventLoopCount % 50 == 1) {
            final isOutput = isEventOutput(event);
            final isError = isEventError(event);
            final isExit = isEventExit(event);
            debugPrint('  → isOutput=$isOutput, isError=$isError, isExit=$isExit');
          }

          if (isEventOutput(event)) {
            final data = getEventData(event);
            debugPrint('  → Output data size: ${data.length} bytes');
            if (data.isNotEmpty) {
              try {
                // FIX: Use proper UTF-8 decoder for Vietnamese/emoji support
                // utf8.decode() handles multi-byte chars correctly (à, 你, 🚀)
                // allowMalformed: true prevents crashes on invalid UTF-8
                final text = utf8.decode(data, allowMalformed: true);

                // Add to output buffer (limits memory growth)
                _outputBuffer.add(text);

                // Write to terminal for display
                state.terminal.write(text);
                debugPrint('  → Written to terminal: ${text.length} chars');

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
                debugPrint('⚠️ UTF-8 decode failed: $e');
                final text = String.fromCharCodes(data);
                _outputBuffer.add(text);
                state.terminal.write(text);
              }
            }
          } else if (isEventError(event)) {
            final message = getEventErrorMessage(event);
            final errorText = '\x1b[31mError: $message\x1b[0m\r\n';
            _outputBuffer.add(errorText);
            state.terminal.write(errorText);
          } else if (isEventExit(event)) {
            final code = getEventExitCode(event);
            final exitText = '\r\n\x1b[33mProcess exited with code $code\x1b[0m\r\n';
            _outputBuffer.add(exitText);
            state.terminal.write(exitText);
          }
        } catch (e) {
          // Log for debugging - event loop errors
          debugPrint('❌ [EventLoop] Error: $e');
        }
      },
    );

    // Start health check timer - monitors if event loop is receiving events
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!_isEventLoopHealthy && !_isDisposed && _eventLoopTimer != null) {
          debugPrint('⚠️ [EventLoop] No events for 5 seconds - PTY may be dead or disconnected');
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
