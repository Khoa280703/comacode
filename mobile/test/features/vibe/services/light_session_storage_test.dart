import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:comacode/features/vibe/services/light_session_storage.dart';

/// Mock path provider for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempDir;

  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LightSessionStorage storage;

  setUp(() async {
    // Create temp directory for tests
    tempDir = await Directory.systemTemp.createTemp('light_storage_test_');

    // Mock path provider
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);

    storage = LightSessionStorage();
  });

  tearDown(() async {
    await storage.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LightSessionStorage', () {
    group('init', () {
      test('should create sessions directory', () async {
        await storage.init('test-session');

        final sessionsDir = Directory('${tempDir.path}/sessions');
        expect(await sessionsDir.exists(), isTrue);
      });

      test('should create storage file path', () async {
        await storage.init('test-session');

        // File should not exist yet (no data written)
        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.exists(), isFalse);
      });
    });

    group('append and flush', () {
      test('should write data to file after debounce', () async {
        await storage.init('test-session');

        storage.append('Hello World');

        // Wait for debounce (1s) + buffer
        await Future.delayed(const Duration(milliseconds: 1200));

        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('Hello World'));
      });

      test('should accumulate data in buffer during debounce', () async {
        await storage.init('test-session');

        storage.append('Hello ');
        await Future.delayed(const Duration(milliseconds: 100));
        storage.append('World');

        // Wait for debounce
        await Future.delayed(const Duration(milliseconds: 1200));

        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.readAsString(), equals('Hello World'));
      });

      test('should append to existing file', () async {
        await storage.init('test-session');

        storage.append('First');
        await Future.delayed(const Duration(milliseconds: 1200));

        storage.append(' Second');
        await Future.delayed(const Duration(milliseconds: 1200));

        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.readAsString(), equals('First Second'));
      });
    });

    group('load', () {
      test('should return empty stream for non-existent file', () async {
        await storage.init('non-existent');

        final chunks = await storage.load().toList();
        expect(chunks, isEmpty);
      });

      test('should stream file content', () async {
        await storage.init('test-session');

        // Write directly to file
        final file = File('${tempDir.path}/sessions/test-session.txt');
        await file.parent.create(recursive: true);
        await file.writeAsString('Test content here');

        final chunks = await storage.load().toList();
        expect(chunks.join(), equals('Test content here'));
      });
    });

    group('clear', () {
      test('should delete storage file', () async {
        await storage.init('test-session');

        // Create file
        final file = File('${tempDir.path}/sessions/test-session.txt');
        await file.parent.create(recursive: true);
        await file.writeAsString('Test content');

        await storage.clear();

        expect(await file.exists(), isFalse);
      });

      test('should clear pending buffer', () async {
        await storage.init('test-session');

        storage.append('Pending data');
        await storage.clear();

        // Wait for any pending timers
        await Future.delayed(const Duration(milliseconds: 1200));

        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.exists(), isFalse);
      });
    });

    group('flushOnPause', () {
      test('should flush immediately without waiting debounce', () async {
        await storage.init('test-session');

        storage.append('Immediate flush');
        await storage.flushOnPause();

        final file = File('${tempDir.path}/sessions/test-session.txt');
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('Immediate flush'));
      });
    });

    group('dispose', () {
      test('should flush pending data before dispose', () async {
        // Create new storage instance for this test
        final testStorage = LightSessionStorage();
        await testStorage.init('test-dispose');

        testStorage.append('Pending on dispose');
        await testStorage.dispose();

        final file = File('${tempDir.path}/sessions/test-dispose.txt');
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('Pending on dispose'));
      });
    });
  });
}
