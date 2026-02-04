import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:comacode/features/terminal/keystroke_batcher.dart';

void main() {
  group('KeystrokeBatcher', () {
    test('batches rapid keystrokes within window', () async {
      final batches = <List<int>>[];
      final seqNums = <int>[];
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) {
          batches.add(bytes);
          seqNums.add(seq);
        },
      );

      // Simulate rapid typing
      batcher.add([0x68]); // h
      batcher.add([0x65]); // e
      batcher.add([0x6C]); // l
      batcher.add([0x6C]); // l
      batcher.add([0x6F]); // o

      // Wait for batch window
      await Future.delayed(const Duration(milliseconds: 20));

      expect(batches.length, 1);
      expect(batches[0], [0x68, 0x65, 0x6C, 0x6C, 0x6F]);
      expect(seqNums[0], greaterThan(0));

      batcher.dispose();
    });

    test('flushes immediately when told', () {
      final batches = <List<int>>[];
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) => batches.add(bytes),
      );

      batcher.add([0x68]); // h
      batcher.flushNow();

      expect(batches.length, 1);
      expect(batches[0], [0x68]);

      batcher.dispose();
    });

    test('tracks sequence numbers correctly', () {
      final seqNums = <int>[];
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) => seqNums.add(seq),
      );

      batcher.add([0x61]);
      batcher.flushNow();
      batcher.add([0x62]);
      batcher.flushNow();

      expect(seqNums.length, 2);
      expect(seqNums[1], greaterThan(seqNums[0]));

      batcher.dispose();
    });

    test('detects fast typing state', () async {
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) {},
      );

      expect(batcher.isTypingFast, false);

      batcher.add([0x61]);
      expect(batcher.isTypingFast, true);

      // Wait for typing to be considered slow
      await Future.delayed(const Duration(milliseconds: 110));
      expect(batcher.isTypingFast, false);

      batcher.dispose();
    });

    test('handles empty batches gracefully', () async {
      final batches = <List<int>>[];
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) => batches.add(bytes),
      );

      // Just wait for window to expire without adding anything
      await Future.delayed(const Duration(milliseconds: 20));

      // Should not have flushed empty buffer
      expect(batches.length, 0);

      batcher.dispose();
    });

    test('multiple batches accumulate separately', () async {
      final batches = <List<int>>[];
      final batcher = KeystrokeBatcher(
        batchWindow: const Duration(milliseconds: 15),
        onFlush: (bytes, seq) => batches.add(bytes),
      );

      // First batch
      batcher.add([0x61]);
      batcher.flushNow();

      // Wait for timer reset
      await Future.delayed(const Duration(milliseconds: 5));

      // Second batch
      batcher.add([0x62]);
      batcher.flushNow();

      expect(batches.length, 2);
      expect(batches[0], [0x61]);
      expect(batches[1], [0x62]);

      batcher.dispose();
    });
  });
}
