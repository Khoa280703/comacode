import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/models.dart';

/// Local storage for projects per connection
///
/// Phase 01: Project & Session Management
/// Storage key pattern: "projects_{connectionFingerprint}"
class ProjectStorage {
  static const String _keyPrefix = 'projects_';

  /// Get storage key for connection
  static String _key(String fingerprint) => '$_keyPrefix$fingerprint';

  /// Save all projects for specific connection
  static Future<void> saveProjects(
    String fingerprint,
    List<Project> projects,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(fingerprint);
      final jsonData = jsonEncode(
        projects.map((p) => p.toJson()).toList(),
      );
      await prefs.setString(key, jsonData);
    } catch (e) {
      throw ProjectStorageException('Failed to save projects: $e');
    }
  }

  /// Load all projects for specific connection
  static Future<List<Project>> loadProjects(String fingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(fingerprint);
      final jsonData = prefs.getString(key);

      if (jsonData == null) return const [];

      final List<dynamic> jsonList = jsonDecode(jsonData);
      return jsonList
          .map((json) =>
              Project.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ProjectStorageException('Failed to load projects: $e');
    }
  }

  /// Add new project to storage
  static Future<void> addProject(
    String fingerprint,
    Project project,
  ) async {
    try {
      final projects = await loadProjects(fingerprint);
      final updated = [...projects, project];
      await saveProjects(fingerprint, updated);
    } catch (e) {
      throw ProjectStorageException('Failed to add project: $e');
    }
  }

  /// Update existing project
  static Future<void> updateProject(
    String fingerprint,
    Project project,
  ) async {
    try {
      final projects = await loadProjects(fingerprint);
      final index = projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) {
        final updated = List<Project>.from(projects);
        updated[index] = project;
        await saveProjects(fingerprint, updated);
      }
    } catch (e) {
      throw ProjectStorageException('Failed to update project: $e');
    }
  }

  /// Delete project from storage
  static Future<void> deleteProject(
    String fingerprint,
    String projectId,
  ) async {
    try {
      final projects = await loadProjects(fingerprint);
      final updated = projects.where((p) => p.id != projectId).toList();
      await saveProjects(fingerprint, updated);
    } catch (e) {
      throw ProjectStorageException('Failed to delete project: $e');
    }
  }

  /// Clear all projects for a connection
  static Future<void> clearProjects(String fingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(fingerprint));
    } catch (e) {
      throw ProjectStorageException('Failed to clear projects: $e');
    }
  }

  /// Check if any projects exist for connection
  static Future<bool> hasProjects(String fingerprint) async {
    try {
      final projects = await loadProjects(fingerprint);
      return projects.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Add session to project
  static Future<void> addSession(
    String fingerprint,
    String projectId,
    SessionMetadata session,
  ) async {
    try {
      final projects = await loadProjects(fingerprint);
      final index = projects.indexWhere((p) => p.id == projectId);
      if (index >= 0) {
        final updatedProject = projects[index].addSession(session);
        final updated = List<Project>.from(projects);
        updated[index] = updatedProject;
        await saveProjects(fingerprint, updated);
      }
    } catch (e) {
      throw ProjectStorageException('Failed to add session: $e');
    }
  }

  /// Remove session from project
  static Future<void> removeSession(
    String fingerprint,
    String projectId,
    String sessionId,
  ) async {
    try {
      final projects = await loadProjects(fingerprint);
      final index = projects.indexWhere((p) => p.id == projectId);
      if (index >= 0) {
        final updatedProject = projects[index].removeSession(sessionId);
        final updated = List<Project>.from(projects);
        updated[index] = updatedProject;
        await saveProjects(fingerprint, updated);
      }
    } catch (e) {
      throw ProjectStorageException('Failed to remove session: $e');
    }
  }
}

/// Exception for ProjectStorage errors
class ProjectStorageException implements Exception {
  final String message;
  ProjectStorageException(this.message);

  @override
  String toString() => 'ProjectStorageException: $message';
}
