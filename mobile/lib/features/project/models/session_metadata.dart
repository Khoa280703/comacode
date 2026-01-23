import 'package:uuid/uuid.dart';

/// Session metadata (lightweight, no Terminal)
///
/// Phase 01: Project & Session Management
/// Stores session info for local persistence - PTY is ephemeral
class SessionMetadata {
  final String id;
  final String name; // e.g. "Session 1", "Fix login bug"
  final DateTime createdAt;

  const SessionMetadata({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// Create new session with UUID
  factory SessionMetadata.create({required String name}) {
    return SessionMetadata(
      id: const Uuid().v4(),
      name: name,
      createdAt: DateTime.now(),
    );
  }

  /// Copy with modified fields
  SessionMetadata copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return SessionMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory SessionMetadata.fromJson(Map<String, dynamic> json) {
    return SessionMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SessionMetadata(id: $id, name: $name)';
}
