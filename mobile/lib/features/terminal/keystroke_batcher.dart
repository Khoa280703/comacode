import 'dart:async';
import 'dart:typed_data';

/// Batches keystrokes with adaptive window for SSH Terminal Mode
///
/// Reduces network traffic by batching rapid keystrokes into single messages.
/// Control characters (Ctrl+C, Tab, etc.) bypass batching for immediate delivery.
class KeystrokeBatcher {
  /// Maximum time to wait before flushing (ms)
  final Duration batchWindow;

  /// Callback when batch is ready to send
  final void Function(List<int> bytes, int sequenceNum) onFlush;

  Timer? _flushTimer;
  final List<int> _buffer = [];
  int _sequenceNum = 0;
  DateTime? _lastKeystroke;

  KeystrokeBatcher({
    required this.batchWindow,
    required this.onFlush,
  });

  /// Get next sequence number (for immediate sends)
  int nextSequenceNum() => ++_sequenceNum;

  /// Add bytes to batch
  void add(List<int> bytes) {
    _buffer.addAll(bytes);
    _lastKeystroke = DateTime.now();

    // Reset timer
    _flushTimer?.cancel();
    _flushTimer = Timer(batchWindow, _flush);
  }

  /// Flush immediately (for control chars)
  void flushNow() {
    _flushTimer?.cancel();
    _flush();
  }

  void _flush() {
    if (_buffer.isEmpty) return;

    final bytes = List<int>.from(_buffer);
    _buffer.clear();

    final seq = ++_sequenceNum;
    onFlush(bytes, seq);
  }

  /// Check if currently batching (typing fast)
  bool get isTypingFast {
    if (_lastKeystroke == null) return false;
    return DateTime.now().difference(_lastKeystroke!) <
           const Duration(milliseconds: 100);
  }

  void dispose() {
    _flushTimer?.cancel();
    _buffer.clear();
  }
}
