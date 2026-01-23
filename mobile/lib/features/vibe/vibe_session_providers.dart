import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_wrapper.dart';
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
                state.terminal.write(text);
              } catch (e) {
                // Ignore decode errors
              }
            }
          } else if (isEventError(event)) {
            final message = getEventErrorMessage(event);
            state.terminal
                .write('\x1b[31mError: $message\x1b[0m\r\n');
          } else if (isEventExit(event)) {
            final code = getEventExitCode(event);
            state.terminal
                .write('\r\n\x1b[33mProcess exited with code $code\x1b[0m\r\n');
          }
        } catch (e) {
          // Silent ignore
        }
      },
    );
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
