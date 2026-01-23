import 'package:xterm/xterm.dart';

import 'session_status.dart';

/// Single Vibe session model
///
/// Phase 02: Multi-Session Tab Architecture
/// Each session represents a PTY connection to a project
class VibeSession {
  final String id;
  final String projectName; // e.g., "api", "mobile", "web"
  final String projectPath; // e.g., ~/dev/api
  final SessionStatus status;
  final Terminal terminal;
  final DateTime createdAt;
  final DateTime lastActive;

  const VibeSession({
    required this.id,
    required this.projectName,
    required this.projectPath,
    required this.status,
    required this.terminal,
    required this.createdAt,
    required this.lastActive,
  });

  /// Create a new session
  factory VibeSession.create({
    required String projectName,
    required String projectPath,
    required Terminal terminal,
  }) {
    final now = DateTime.now();
    return VibeSession(
      id: now.millisecondsSinceEpoch.toString(),
      projectName: projectName,
      projectPath: projectPath,
      status: SessionStatus.active,
      terminal: terminal,
      createdAt: now,
      lastActive: now,
    );
  }

  /// Copy with modified fields
  VibeSession copyWith({
    String? id,
    String? projectName,
    String? projectPath,
    SessionStatus? status,
    Terminal? terminal,
    DateTime? createdAt,
    DateTime? lastActive,
  }) {
    return VibeSession(
      id: id ?? this.id,
      projectName: projectName ?? this.projectName,
      projectPath: projectPath ?? this.projectPath,
      status: status ?? this.status,
      terminal: terminal ?? this.terminal,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  /// Update last active time
  VibeSession touch() {
    return copyWith(lastActive: DateTime.now());
  }

  /// Check if session is stale (idle > 30 min)
  bool get isStale {
    final diff = DateTime.now().difference(lastActive);
    return diff.inMinutes > 30;
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectName': projectName,
      'projectPath': projectPath,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'lastActive': lastActive.toIso8601String(),
    };
  }

  /// Create from JSON
  factory VibeSession.fromJson(Map<String, dynamic> json, Terminal terminal) {
    return VibeSession(
      id: json['id'] as String,
      projectName: json['projectName'] as String,
      projectPath: json['projectPath'] as String,
      status: SessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SessionStatus.idle,
      ),
      terminal: terminal,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActive: DateTime.parse(json['lastActive'] as String),
    );
  }
}
