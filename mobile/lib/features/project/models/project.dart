import 'package:uuid/uuid.dart';

import 'session_metadata.dart';

/// Project model (local storage only)
///
/// Phase 01: Project & Session Management
/// Per-connection project storage with session list
class Project {
  final String id; // UUID
  final String name; // e.g. "my-app", "api-server"
  final String path; // e.g. "/Users/dev/my-app"
  final DateTime createdAt;
  final DateTime lastAccessed;
  final List<SessionMetadata> sessions;

  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.lastAccessed,
    this.sessions = const [],
  });

  /// Create new project with UUID
  factory Project.create({
    required String name,
    required String path,
  }) {
    final now = DateTime.now();
    return Project(
      id: const Uuid().v4(),
      name: name,
      path: path,
      createdAt: now,
      lastAccessed: now,
    );
  }

  /// Copy with modified fields
  Project copyWith({
    String? id,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? lastAccessed,
    List<SessionMetadata>? sessions,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      sessions: sessions ?? this.sessions,
    );
  }

  /// Update last accessed time
  Project touch() {
    return copyWith(lastAccessed: DateTime.now());
  }

  /// Add session to project
  Project addSession(SessionMetadata session) {
    return copyWith(sessions: [...sessions, session]);
  }

  /// Remove session from project
  Project removeSession(String sessionId) {
    return copyWith(
      sessions: sessions.where((s) => s.id != sessionId).toList(),
    );
  }

  /// Update session in project
  Project updateSession(SessionMetadata updated) {
    return copyWith(
      sessions: sessions
          .map((s) => s.id == updated.id ? updated : s)
          .toList(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessed': lastAccessed.toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      sessions: (json['sessions'] as List<dynamic>?)
              ?.map((s) => SessionMetadata.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Project(id: $id, name: $name, path: $path, sessions: ${sessions.length})';
}
