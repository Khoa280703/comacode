import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' show Terminal;
import 'keystroke_batcher.dart';
import 'prediction_engine.dart';

/// Handles raw keyboard input for SSH terminal mode
///
/// Phase Fix-03: Pure SSH mode - all keys go directly to terminal.
/// Chat-style TextField has been removed.
class SshInputHandler {
  final Terminal terminal;
  final void Function(List<int> bytes, int sequenceNum) onKeyBatch;

  late final KeystrokeBatcher _batcher;
  PredictionEngine? _predictionEngine;
  bool _isAttached = false;

  SshInputHandler({
    required this.terminal,
    required this.onKeyBatch,
  }) : _batcher = KeystrokeBatcher(
      batchWindow: const Duration(milliseconds: 15),
      onFlush: onKeyBatch,
    );

  /// Start capturing keyboard events
  void attach() {
    if (_isAttached) return;
    _isAttached = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// Attach with prediction engine for speculative local echo
  void attachWithPrediction(PredictionEngine predictionEngine) {
    _predictionEngine = predictionEngine;
    attach();
  }

  /// Stop capturing keyboard events
  void detach() {
    _isAttached = false;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _batcher.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Only handle key down and repeat
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    // Phase Fix-03: REMOVED textFieldFocusNode check
    // Pure SSH mode - all keys go directly to terminal
    // (Chat-style UI with TextField has been removed)

    // Convert to terminal escape sequence
    final bytes = _convertToBytes(event);
    if (bytes.isEmpty) return false;

    // Classify and route
    if (_isControlChar(event)) {
      // Category A: Send immediately (Ctrl+C, ESC, Tab, F-keys)
      _sendImmediate(bytes);
    } else {
      // Category B: Check prediction or add to batch
      if (_predictionEngine?.shouldPredict(bytes) ?? false) {
        final seq = _batcher.nextSequenceNum();
        _predictionEngine!.applyPrediction(bytes, seq);
        _batcher.add(bytes);
      } else {
        _batcher.add(bytes);
      }
    }

    return true;  // Mark as handled
  }


  /// Convert KeyEvent to terminal byte sequence
  List<int> _convertToBytes(KeyEvent event) {
    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Control characters (Ctrl+A = 0x01, ..., Ctrl+Z = 0x1A)
    if (isCtrl && !isAlt) {
      // Ctrl+Letter -> control codes 0x01-0x1A
      if (key.keyLabel.length == 1) {
        final char = key.keyLabel.toUpperCase().codeUnitAt(0);
        if (char >= 65 && char <= 90) {  // A-Z
          return [char - 64];  // Convert to control code
        }
      }
      // Special: Ctrl+@ = 0x00 (NUL)
      if (key == LogicalKeyboardKey.digit2) return [0x00];
      // Ctrl+[ = 0x1B (ESC) - same as pressing ESC
      if (key == LogicalKeyboardKey.bracketLeft) return [0x1B];
      // Ctrl+\ = 0x1C (FS)
      if (key == LogicalKeyboardKey.backslash) return [0x1C];
      // Ctrl+] = 0x1D (GS)
      if (key == LogicalKeyboardKey.bracketRight) return [0x1D];
      // Ctrl+^ = 0x1E (RS)
      if (key == LogicalKeyboardKey.caret) return [0x1E];
      // Ctrl+_ = 0x1F (US)
      if (key == LogicalKeyboardKey.underscore) return [0x1F];
      // Special: Ctrl+? = 0x7F (DEL)
      if (key == LogicalKeyboardKey.slash) return [0x7F];
    }

    // Alt combinations (Meta key) - ESC + char
    if (isAlt && !isCtrl) {
      if (key.keyLabel.length == 1) {
        return [0x1B, key.keyLabel.codeUnitAt(0)];  // ESC + char
      }
    }

    // Special keys
    switch (key) {
      case LogicalKeyboardKey.enter:
        return [0x0D];  // CR
      case LogicalKeyboardKey.tab:
        return [0x09];
      case LogicalKeyboardKey.escape:
        return [0x1B];
      case LogicalKeyboardKey.backspace:
        return [0x7F];
      case LogicalKeyboardKey.arrowUp:
        return [0x1B, 0x5B, 0x41];  // ESC[A
      case LogicalKeyboardKey.arrowDown:
        return [0x1B, 0x5B, 0x42];  // ESC[B
      case LogicalKeyboardKey.arrowRight:
        return [0x1B, 0x5B, 0x43];  // ESC[C
      case LogicalKeyboardKey.arrowLeft:
        return [0x1B, 0x5B, 0x44];  // ESC[D
      case LogicalKeyboardKey.home:
        return [0x1B, 0x5B, 0x48];  // ESC[H
      case LogicalKeyboardKey.end:
        return [0x1B, 0x5B, 0x46];  // ESC[F
      case LogicalKeyboardKey.pageUp:
        return [0x1B, 0x5B, 0x35, 0x7E];  // ESC[5~
      case LogicalKeyboardKey.pageDown:
        return [0x1B, 0x5B, 0x36, 0x7E];  // ESC[6~
      case LogicalKeyboardKey.delete:
        return [0x1B, 0x5B, 0x33, 0x7E];  // ESC[3~
      case LogicalKeyboardKey.insert:
        return [0x1B, 0x5B, 0x32, 0x7E];  // ESC[2~
      default:
        break;
    }

    // F1-F12 function keys
    final f1Key = LogicalKeyboardKey.f1;
    final f12Key = LogicalKeyboardKey.f12;
    if (key.keyId >= f1Key.keyId && key.keyId <= f12Key.keyId) {
      final fNum = key.keyId - f1Key.keyId + 1;
      // F1-F4: ESC OP, OQ, OR, OS (vt100)
      if (fNum <= 4) {
        return [0x1B, 0x4F, 0x50 + fNum - 1];  // ESC[O P-Q-R-S
      }
      // F5-F12: ESC [15~, ESC[17~, etc.
      final codes = [15, 17, 18, 19, 20, 21, 23, 24];
      if (fNum <= 12) {
        final code = codes[fNum - 5];
        return [0x1B, 0x5B, ...code.toString().codeUnits, 0x7E];
      }
    }

    // Regular character - use character if available
    if (event.character != null && event.character!.isNotEmpty) {
      return event.character!.codeUnits;
    }

    return [];
  }

  /// Check if this is a control character that should bypass batching
  bool _isControlChar(KeyEvent event) {
    final key = event.logicalKey;

    // Explicit control modifiers
    if (HardwareKeyboard.instance.isControlPressed) return true;

    // Special keys that should be sent immediately
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.tab) {
      return true;
    }

    // F-keys
    final f1Key = LogicalKeyboardKey.f1;
    final f12Key = LogicalKeyboardKey.f12;
    if (key.keyId >= f1Key.keyId && key.keyId <= f12Key.keyId) {
      return true;
    }

    return false;
  }

  void _sendImmediate(List<int> bytes) {
    final seq = _batcher.nextSequenceNum();
    onKeyBatch(bytes, seq);
  }
}
