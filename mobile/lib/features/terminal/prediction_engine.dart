import 'dart:collection';
import 'dart:typed_data';
import 'package:xterm/xterm.dart';

/// Speculative local echo engine (Mosh-inspired)
///
/// Predicts keystroke output locally for instant feedback,
/// then confirms/rolls back based on server response.
class PredictionEngine {
  final Terminal terminal;
  final void Function(Duration rtt) onLatencyUpdate;

  final Queue<PredictionRecord> _pending = Queue();
  bool _enabled = false;
  bool _inPasswordMode = false;
  Duration _currentLatency = Duration.zero;

  PredictionEngine({
    required this.terminal,
    required this.onLatencyUpdate,
  });

  /// Check if prediction should be enabled based on latency
  void updateLatency(Duration rtt) {
    _currentLatency = rtt;
    // Enable prediction only on high-latency links (>50ms)
    _enabled = rtt.inMilliseconds > 50;
    onLatencyUpdate(rtt);
  }

  /// Check if we should predict this keystroke
  bool shouldPredict(List<int> bytes) {
    if (!_enabled) return false;
    if (_inPasswordMode) return false;
    if (bytes.isEmpty) return false;

    // Only predict single printable ASCII characters
    if (bytes.length != 1) return false;
    final byte = bytes[0];

    // Printable ASCII: 0x20 (space) to 0x7E (~)
    return byte >= 0x20 && byte <= 0x7E;
  }

  /// Apply prediction locally (display character immediately)
  void applyPrediction(List<int> bytes, int sequenceNum) {
    if (bytes.length != 1) return;

    final char = String.fromCharCode(bytes[0]);
    final cursorPos = _getCursorPosition();

    // Write character to terminal immediately
    // Note: In full implementation, would use gray text
    terminal.write(char);

    _pending.add(PredictionRecord(
      sequenceNum: sequenceNum,
      char: char,
      cursorX: cursorPos.x,
      cursorY: cursorPos.y,
      timestamp: DateTime.now(),
    ));
  }

  /// Handle server ACK - confirm predictions up to sequence
  void handleAck(int sequenceNum) {
    while (_pending.isNotEmpty && _pending.first.sequenceNum <= sequenceNum) {
      final record = _pending.removeFirst();

      // Calculate actual latency
      final latency = DateTime.now().difference(record.timestamp);
      updateLatency(latency);

      // Prediction confirmed - character already displayed
      // In full implementation, would change gray → normal color
    }
  }

  /// Rollback all pending predictions (on mismatch)
  void rollbackAll() {
    while (_pending.isNotEmpty) {
      final record = _pending.removeFirst();
      // In full implementation: erase predicted character
      // For now, server output will overwrite
    }
  }

  /// Check terminal output for password prompt
  void checkForPasswordPrompt(String output) {
    final patterns = [
      'password:',
      'Password:',
      'Password for',
      'passphrase:',
      'Passphrase:',
      'PIN:',
      'Enter PIN',
      'sudo password',
      '[sudo]',
    ];

    _inPasswordMode = patterns.any((p) => output.contains(p));

    // Also disable on clear password mode indicators
    if (output.contains('\$ ') || output.contains('% ') || output.contains('> ')) {
      // Back to normal prompt
      _inPasswordMode = false;
    }
  }

  /// Get current cursor position from terminal
  CursorPosition _getCursorPosition() {
    return CursorPosition(
      x: terminal.buffer.cursorX,
      y: terminal.buffer.cursorY,
    );
  }

  /// Check if any predictions pending
  bool get hasPendingPredictions => _pending.isNotEmpty;

  /// Get number of pending predictions
  int get pendingCount => _pending.length;

  /// Check if prediction is enabled
  bool get isEnabled => _enabled;

  /// Get current latency
  Duration get currentLatency => _currentLatency;

  void dispose() {
    _pending.clear();
  }
}

/// Record of a predicted character
class PredictionRecord {
  final int sequenceNum;
  final String char;
  final int cursorX;
  final int cursorY;
  final DateTime timestamp;

  PredictionRecord({
    required this.sequenceNum,
    required this.char,
    required this.cursorX,
    required this.cursorY,
    required this.timestamp,
  });
}

/// Cursor position helper
class CursorPosition {
  final int x;
  final int y;

  CursorPosition({required this.x, required this.y});
}
