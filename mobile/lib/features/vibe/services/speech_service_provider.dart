import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_service.dart';

/// Provider for SpeechService
///
/// Phase 02: Dictation Integration
final speechServiceProvider =
    StateNotifierProvider<SpeechServiceNotifier, SpeechState>((ref) {
  return SpeechServiceNotifier();
});

/// Notifier for SpeechService state management
class SpeechServiceNotifier extends StateNotifier<SpeechState> {
  SpeechService? _service;

  SpeechServiceNotifier() : super(const SpeechState());

  /// Get or create the service instance
  SpeechService get _speechService {
    _service ??= SpeechService();
    return _service!;
  }

  /// Initialize speech recognition
  Future<void> initialize() async {
    final success = await _speechService.initialize();
    state = state.copyWith(isInitialized: success);
  }

  /// Start listening with Vietnamese language
  Future<bool> startListening({
    required Function(String text) onResult,
  }) async {
    final success = await _speechService.startListening(
      onResult: (text) {
        state = state.copyWith(lastRecognizedText: text);
        onResult(text);
      },
    );
    state = state.copyWith(isListening: success);
    return success;
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _speechService.stopListening();
    state = state.copyWith(isListening: false);
  }

  /// Cancel listening immediately
  Future<void> cancel() async {
    await _speechService.cancelListening();
    state = state.copyWith(isListening: false);
  }
}
