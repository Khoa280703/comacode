import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'models/models.dart';
import 'project_storage.dart';

/// Provider for projects per connection
final projectsProvider =
    FutureProvider.family<List<Project>, String>((ref, fingerprint) async {
  return ProjectStorage.loadProjects(fingerprint);
});

/// Notifier for project CRUD operations
class ProjectNotifier extends StateNotifier<List<Project>> {
  final String _fingerprint;

  ProjectNotifier(this._fingerprint) : super([]) {
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ProjectStorage.loadProjects(_fingerprint);
      state = projects;
    } catch (e) {
      state = [];
    }
  }

  Future<void> addProject(Project project) async {
    await ProjectStorage.addProject(_fingerprint, project);
    await _loadProjects();
  }

  Future<void> updateProject(Project project) async {
    await ProjectStorage.updateProject(_fingerprint, project);
    await _loadProjects();
  }

  Future<void> deleteProject(String projectId) async {
    await ProjectStorage.deleteProject(_fingerprint, projectId);
    await _loadProjects();
  }

  Future<void> addSession(String projectId, SessionMetadata session) async {
    await ProjectStorage.addSession(_fingerprint, projectId, session);
    await _loadProjects();
  }

  Future<void> removeSession(String projectId, String sessionId) async {
    await ProjectStorage.removeSession(_fingerprint, projectId, sessionId);
    await _loadProjects();
  }
}

/// Provider for project notifier
final projectNotifierProvider =
    StateNotifierProvider.family<ProjectNotifier, List<Project>, String>(
        (ref, fingerprint) {
  return ProjectNotifier(fingerprint);
});

/// Current UUID generator
const uuidGenerator = Uuid();
