import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_wrapper.dart';
import 'models/output_buffer.dart';
import 'models/special_key.dart';
import 'models/vibe_session_state.dart';

/// Vibe session state provider
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
  bool _isDisposed = false;

  /// Output buffer to prevent memory issues with large output
  final OutputBuffer _outputBuffer = OutputBuffer();

  /// Send prompt text to backend
  Future<void> sendPrompt(String prompt) async {
    state = state.copyWith(isSending: true, error: null);

    try {
      await _bridge.sendCommand(prompt);
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        error: 'Failed to send prompt: $e',
      );
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

          if (isEventOutput(event)) {
            final data = getEventData(event);
            if (data.isNotEmpty) {
              try {
                final text = String.fromCharCodes(data);

                // Add to output buffer (limits memory growth)
                _outputBuffer.add(text);

                // Write to terminal for display
                state.terminal.write(text);

                // Log buffer stats periodically for monitoring
                if (_outputBuffer.length % 1000 == 0) {
                  final stats = _outputBuffer.stats;
                  if (stats['isFull'] == true) {
                    // Buffer at capacity - oldest lines being dropped
                    print('Output buffer at capacity: ${stats['lines']} lines');
                  }
                }
              } catch (e) {
                // Ignore decode errors
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
          // Silent ignore
        }
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
    super.dispose();
  }
}

// Temporary helper functions - will be replaced with proper bridge methods
bool isEventOutput(dynamic event) => false;
List<int> getEventData(dynamic event) => [];
bool isEventError(dynamic event) => false;
String getEventErrorMessage(dynamic event) => '';
bool isEventExit(dynamic event) => false;
int getEventExitCode(dynamic event) => 0;
