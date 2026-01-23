import 'package:flutter_test/flutter_test.dart';
import 'package:comacode/features/project/models/models.dart';

void main() {
  group('SessionMetadata', () {
    test('create generates UUID', () {
      final session = SessionMetadata.create(name: 'Test Session');
      expect(session.id, isNotEmpty);
      expect(session.name, 'Test Session');
      expect(session.createdAt, isNotNull);
    });

    test('copyWith updates fields', () {
      final session = SessionMetadata.create(name: 'Original');
      final updated = session.copyWith(name: 'Updated');
      expect(updated.id, session.id);
      expect(updated.name, 'Updated');
    });

    test('toJson/fromJson roundtrip', () {
      final original = SessionMetadata.create(name: 'Roundtrip');
      final json = original.toJson();
      final restored = SessionMetadata.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.createdAt, original.createdAt);
    });

    test('equality by id', () {
      final s1 = SessionMetadata(id: 'same', name: 'A', createdAt: DateTime.now());
      final s2 = SessionMetadata(id: 'same', name: 'B', createdAt: DateTime.now());
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });
  });

  group('Project', () {
    test('create generates UUID', () {
      final project = Project.create(name: 'test-app', path: '/dev/test');
      expect(project.id, isNotEmpty);
      expect(project.name, 'test-app');
      expect(project.path, '/dev/test');
      expect(project.sessions, isEmpty);
    });

    test('touch updates lastAccessed', () {
      final project = Project.create(name: 'test', path: '/tmp');
      final touched = project.touch();
      expect(touched.lastAccessed.isAfter(project.lastAccessed), isTrue);
    });

    test('addSession appends session', () {
      final project = Project.create(name: 'test', path: '/tmp');
      final session = SessionMetadata.create(name: 'Session 1');
      final withSession = project.addSession(session);
      expect(withSession.sessions, hasLength(1));
      expect(withSession.sessions.first.name, 'Session 1');
    });

    test('removeSession removes by id', () {
      final session1 = SessionMetadata.create(name: 'S1');
      final session2 = SessionMetadata.create(name: 'S2');
      final project = Project.create(name: 'test', path: '/tmp')
          .addSession(session1)
          .addSession(session2);
      final without = project.removeSession(session1.id);
      expect(without.sessions, hasLength(1));
      expect(without.sessions.first.id, session2.id);
    });

    test('updateSession replaces session', () {
      final original = SessionMetadata.create(name: 'Original');
      final project = Project.create(name: 'test', path: '/tmp').addSession(original);
      final updated = original.copyWith(name: 'Updated');
      final withUpdate = project.updateSession(updated);
      expect(withUpdate.sessions, hasLength(1));
      expect(withUpdate.sessions.first.name, 'Updated');
    });

    test('toJson/fromJson roundtrip', () {
      final original = Project.create(name: 'app', path: '/dev/app')
          .addSession(SessionMetadata.create(name: 'S1'));
      final json = original.toJson();
      final restored = Project.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.path, original.path);
      expect(restored.sessions, hasLength(1));
      expect(restored.sessions.first.name, 'S1');
    });

    test('equality by id', () {
      final p1 = Project(
        id: 'same',
        name: 'A',
        path: '/a',
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
      );
      final p2 = Project(
        id: 'same',
        name: 'B',
        path: '/b',
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
      );
      expect(p1, equals(p2));
    });
  });
}
