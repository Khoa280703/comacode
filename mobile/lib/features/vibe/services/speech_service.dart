import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech recognition service for Vibe Coding dictation
///
/// Phase 02: Dictation Integration
/// Supports Vietnamese language with real-time recognition
class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _isAvailable = false;
  bool _isListening = false;
  String _lastError = '';

  /// Check if speech recognition is available
  bool get isAvailable => _isAvailable;

  /// Currently listening state
  bool get isListening => _isListening;

  /// Last error message
  String get lastError => _lastError;

  /// Initialize speech recognition
  /// Must be called before other methods
  Future<bool> initialize() async {
    try {
      _isAvailable = await _speech.initialize(
        onError: (error) {
          _lastError = error.errorMsg;
          debugPrint('🎤 Speech error: $error');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('🎤 Speech status: $status');
          _isListening = status == 'listening';
        },
      );
      return _isAvailable;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('🎤 Speech init error: $e');
      return false;
    }
  }

  /// Start listening with Vietnamese language
  ///
  /// [onResult] callback receives recognized text
  /// [listenFor] maximum duration to listen (default: 30s)
  /// [pauseFor] pause duration on silence (default: 3s)
  Future<bool> startListening({
    required Function(String text) onResult,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_isAvailable) {
      _lastError = 'Speech not available. Call initialize() first.';
      return false;
    }

    if (_isListening) {
      await stopListening();
    }

    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            onResult(text);
          }
        },
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: 'vi_VN', // Vietnamese
        // ignore: deprecated_member_use
        listenMode: ListenMode.confirmation,
        // ignore: deprecated_member_use
        cancelOnError: true,
        // ignore: deprecated_member_use
        partialResults: true, // Real-time updates
      );
      _isListening = true;
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('🎤 Listen error: $e');
      return false;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  /// Cancel listening immediately
  Future<void> cancelListening() async {
    await _speech.cancel();
    _isListening = false;
  }

  /// Get available locales (for language picker)
  Future<List<LocaleName>> getLocales() async {
    return await _speech.locales();
  }
}

/// Speech recognition state for UI
class SpeechState {
  final bool isInitialized;
  final bool isListening;
  final String lastRecognizedText;
  final String? error;

  const SpeechState({
    this.isInitialized = false,
    this.isListening = false,
    this.lastRecognizedText = '',
    this.error,
  });

  SpeechState copyWith({
    bool? isInitialized,
    bool? isListening,
    String? lastRecognizedText,
    String? error,
  }) {
    return SpeechState(
      isInitialized: isInitialized ?? this.isInitialized,
      isListening: isListening ?? this.isListening,
      lastRecognizedText: lastRecognizedText ?? this.lastRecognizedText,
      error: error,
    );
  }
}
