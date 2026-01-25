import 'package:flutter_test/flutter_test.dart';
import 'package:comacode/features/project/models/project.dart';
import 'package:comacode/features/project/models/session_metadata.dart';

void main() {
  group('Project', () {
    test('should create project with correct properties', () {
      final project = Project.create(
        name: 'test-app',
        path: '/Users/dev/test-app',
      );

      expect(project.name, 'test-app');
      expect(project.path, '/Users/dev/test-app');
      expect(project.sessions, isEmpty);
      expect(project.id, isNotEmpty);
      expect(project.createdAt, isNotNull);
      expect(project.lastAccessed, isNotNull);
    });

    test('should copy with modified fields', () {
      final project = Project.create(
        name: 'original',
        path: '/path',
      );

      final updated = project.copyWith(name: 'updated');

      expect(updated.name, 'updated');
      expect(updated.path, '/path');
      expect(project.name, 'original'); // Original unchanged
    });

    test('should add session to project', () {
      final project = Project.create(
        name: 'test',
        path: '/path',
      );
      final session = SessionMetadata.create(name: 'Session 1');

      final updated = project.addSession(session);

      expect(updated.sessions.length, 1);
      expect(updated.sessions.first.name, 'Session 1');
      expect(project.sessions, isEmpty); // Original unchanged
    });

    test('should remove session from project', () {
      final session1 = SessionMetadata.create(name: 'S1');
      final session2 = SessionMetadata.create(name: 'S2');
      final project = Project.create(name: 'test', path: '/path')
          .addSession(session1)
          .addSession(session2);

      final updated = project.removeSession(session1.id);

      expect(updated.sessions.length, 1);
      expect(updated.sessions.first.id, session2.id);
    });

    test('should serialize and deserialize to JSON', () {
      final session = SessionMetadata.create(name: 'Test Session');
      final project = Project.create(
        name: 'my-app',
        path: '/Users/dev/my-app',
      ).addSession(session);

      final json = project.toJson();
      final restored = Project.fromJson(json);

      expect(restored.id, project.id);
      expect(restored.name, project.name);
      expect(restored.path, project.path);
      expect(restored.sessions.length, 1);
      expect(restored.sessions.first.name, 'Test Session');
    });

    test('should equality check by id', () {
      final project1 = Project.create(name: 'a', path: '/a');
      final project2 = Project(
        id: project1.id,
        name: 'b',
        path: '/b',
        createdAt: project1.createdAt,
        lastAccessed: project1.lastAccessed,
      );

      expect(project1, project2); // Same id
      expect(project1 == Project.create(name: 'x', path: '/y'), isFalse);
    });
  });

  group('SessionMetadata', () {
    test('should create session with correct properties', () {
      final session = SessionMetadata.create(name: 'Test Session');

      expect(session.name, 'Test Session');
      expect(session.id, isNotEmpty);
      expect(session.createdAt, isNotNull);
    });

    test('should serialize and deserialize to JSON', () {
      final session = SessionMetadata.create(name: 'My Session');

      final json = session.toJson();
      final restored = SessionMetadata.fromJson(json);

      expect(restored.id, session.id);
      expect(restored.name, session.name);
      expect(restored.createdAt, session.createdAt);
    });
  });
}
