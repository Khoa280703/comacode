import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:comacode/features/terminal/prediction_engine.dart' hide CursorPosition;
import 'package:comacode/features/terminal/prediction_engine.dart' as prediction;

void main() {
  group('PredictionEngine', () {
    late Terminal terminal;
    late PredictionEngine engine;

    setUp(() {
      terminal = Terminal();
      engine = PredictionEngine(
        terminal: terminal,
        onLatencyUpdate: (_) {},
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('predicts alphanumeric on high latency', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      expect(engine.shouldPredict([0x61]), true); // 'a'
      expect(engine.shouldPredict([0x41]), true); // 'A'
      expect(engine.shouldPredict([0x31]), true); // '1'
      expect(engine.shouldPredict([0x20]), true); // space
    });

    test('does not predict on low latency', () {
      engine.updateLatency(const Duration(milliseconds: 20));

      expect(engine.shouldPredict([0x61]), false);
      expect(engine.isEnabled, false);
    });

    test('enables prediction on high latency', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      expect(engine.isEnabled, true);
    });

    test('does not predict control chars', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      expect(engine.shouldPredict([0x03]), false); // Ctrl+C
      expect(engine.shouldPredict([0x1B]), false); // ESC
      expect(engine.shouldPredict([0x09]), false); // Tab
      expect(engine.shouldPredict([0x0D]), false); // CR (Enter)
      expect(engine.shouldPredict([0x7F]), false); // DEL (Backspace)
    });

    test('does not predict multi-byte sequences', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      expect(engine.shouldPredict([0x1B, 0x5B, 0x41]), false); // Arrow Up
      expect(engine.shouldPredict([]), false); // Empty
    });

    test('disables on password prompt', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      expect(engine.isEnabled, true);
      expect(engine.shouldPredict([0x61]), true);

      engine.checkForPasswordPrompt('Enter password:');
      expect(engine.shouldPredict([0x61]), false);

      engine.checkForPasswordPrompt('\$ ');
      expect(engine.shouldPredict([0x61]), true);
    });

    test('detects various password prompt patterns', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      final patterns = [
        'password:',
        'Password:',
        'Password for user:',
        'passphrase:',
        'Passphrase:',
        'PIN:',
        'Enter PIN',
        'sudo password',
        '[sudo] password for',
      ];

      for (final pattern in patterns) {
        engine.checkForPasswordPrompt(pattern);
        expect(engine.shouldPredict([0x61]), false,
            reason: 'Should detect password pattern: $pattern');
        // Reset for next test
        engine.checkForPasswordPrompt('\$ ');
      }
    });

    test('handles prediction and confirmation', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      // Apply prediction
      engine.applyPrediction([0x61], 1);
      expect(engine.hasPendingPredictions, true);
      expect(engine.pendingCount, 1);

      // Confirm prediction
      engine.handleAck(1);
      expect(engine.hasPendingPredictions, false);
      expect(engine.pendingCount, 0);
    });

    test('handles multiple pending predictions', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      engine.applyPrediction([0x61], 1);
      engine.applyPrediction([0x62], 2);
      engine.applyPrediction([0x63], 3);

      expect(engine.pendingCount, 3);

      // Confirm all at once
      engine.handleAck(3);
      expect(engine.pendingCount, 0);
    });

    test('handles out-of-order ACK', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      engine.applyPrediction([0x61], 1);
      engine.applyPrediction([0x62], 2);
      engine.applyPrediction([0x63], 3);

      expect(engine.pendingCount, 3);

      // ACK seq 2 only
      engine.handleAck(2);
      expect(engine.pendingCount, 1);

      // ACK seq 3
      engine.handleAck(3);
      expect(engine.pendingCount, 0);
    });

    test('rollback clears all predictions', () {
      engine.updateLatency(const Duration(milliseconds: 100));

      engine.applyPrediction([0x61], 1);
      engine.applyPrediction([0x62], 2);

      expect(engine.pendingCount, 2);

      engine.rollbackAll();
      expect(engine.pendingCount, 0);
    });

    test('tracks current latency', () {
      expect(engine.currentLatency, Duration.zero);

      engine.updateLatency(const Duration(milliseconds: 75));

      expect(engine.currentLatency, const Duration(milliseconds: 75));
    });

    test('cleans up on dispose', () {
      engine.updateLatency(const Duration(milliseconds: 100));
      engine.applyPrediction([0x61], 1);

      engine.dispose();

      expect(engine.pendingCount, 0);
    });
  });

  group('CursorPosition', () {
    test('creates valid position', () {
      final pos = prediction.CursorPosition(x: 10, y: 5);

      expect(pos.x, 10);
      expect(pos.y, 5);
    });
  });

  group('PredictionRecord', () {
    test('stores prediction data', () {
      final record = prediction.PredictionRecord(
        sequenceNum: 42,
        char: 'a',
        cursorX: 10,
        cursorY: 5,
        timestamp: DateTime(2026, 1, 31, 12, 0, 0),
      );

      expect(record.sequenceNum, 42);
      expect(record.char, 'a');
      expect(record.cursorX, 10);
      expect(record.cursorY, 5);
    });
  });
}
