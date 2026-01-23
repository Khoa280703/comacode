import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_providers.dart';
import '../../core/theme.dart';
import 'models/models.dart';
import 'project_providers.dart';
import 'widgets/project_list.dart';
import 'widgets/vfs_file_picker.dart';

/// Project Picker Screen
///
/// Phase 02: Project & Session Management
/// Shown after successful connection, before Vibe Session
class ProjectPickerPage extends ConsumerStatefulWidget {
  const ProjectPickerPage({super.key});

  @override
  ConsumerState<ProjectPickerPage> createState() => _ProjectPickerPageState();
}

class _ProjectPickerPageState extends ConsumerState<ProjectPickerPage> {
  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final fingerprint = connectionState.currentHost?.fingerprint ?? '';

    if (fingerprint.isEmpty) {
      return Scaffold(
        backgroundColor: CatppuccinMocha.base,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: CatppuccinMocha.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Not connected',
                style: TextStyle(
                  fontSize: 18,
                  color: CatppuccinMocha.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please connect to a host first',
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        title: const Text('Select Project'),
        backgroundColor: CatppuccinMocha.mantle,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateProjectDialog(context, fingerprint),
            tooltip: 'Add Project',
          ),
        ],
      ),
      body: ProjectList(
        fingerprint: fingerprint,
        onProjectTap: (project) => _showSessions(context, project),
      ),
    );
  }

  void _showCreateProjectDialog(BuildContext context, String fingerprint) {
    final nameController = TextEditingController();
    final pathController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: CatppuccinMocha.surface,
          title: Text(
            'New Project',
            style: TextStyle(color: CatppuccinMocha.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name field
              TextField(
                controller: nameController,
                style: TextStyle(color: CatppuccinMocha.text),
                decoration: InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'e.g., my-app',
                  labelStyle: TextStyle(color: CatppuccinMocha.subtext0),
                  hintStyle: TextStyle(color: CatppuccinMocha.overlay0),
                  filled: true,
                  fillColor: CatppuccinMocha.surface0,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Path field with Browse button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pathController,
                      style: TextStyle(color: CatppuccinMocha.text),
                      decoration: InputDecoration(
                        labelText: 'Project Path',
                        hintText: 'e.g., /Users/dev/my-app',
                        labelStyle: TextStyle(color: CatppuccinMocha.subtext0),
                        hintStyle: TextStyle(color: CatppuccinMocha.overlay0),
                        filled: true,
                        fillColor: CatppuccinMocha.surface0,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      enabled: false, // Use Browse button
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse'),
                    onPressed: () async {
                      // Use VFS FilePicker (reuse existing VfsNotifier)
                      final selectedPath = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const VfsFilePicker()),
                      );
                      if (selectedPath != null) {
                        setDialogState(() {
                          pathController.text = selectedPath;
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: CatppuccinMocha.subtext0),
              ),
            ),
            TextButton(
              onPressed: isCreating
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final path = pathController.text.trim();

                      // Validate inputs
                      if (name.isEmpty || path.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill all fields')),
                        );
                        return;
                      }

                      // Validate project name (no special chars, max 100)
                      if (!_isValidProjectName(name)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Invalid name. Use letters, numbers, -, _ only',
                            ),
                            backgroundColor: CatppuccinMocha.red,
                          ),
                        );
                        return;
                      }

                      // Validate path (absolute, no .. traversal)
                      if (!_isValidPath(path)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invalid path. Must be absolute path'),
                            backgroundColor: CatppuccinMocha.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isCreating = true);

                      final project = Project.create(
                        name: name,
                        path: path,
                      );

                      await ref
                          .read(projectNotifierProvider(fingerprint).notifier)
                          .addProject(project);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Project "$name" created'),
                            backgroundColor: CatppuccinMocha.green,
                          ),
                        );
                      }
                    },
              child: isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CatppuccinMocha.mauve,
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isValidProjectName(String name) {
    // Allow letters, numbers, hyphen, underscore; max 100 chars
    if (name.length > 100) return false;
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    return validPattern.hasMatch(name);
  }

  bool _isValidPath(String path) {
    // Must be absolute path (starts with / on Unix, ~ for home)
    if (!path.startsWith('/') && !path.startsWith('~')) {
      return false;
    }
    // No path traversal attempts
    if (path.contains('..')) {
      return false;
    }
    return true;
  }

  void _showSessions(BuildContext context, Project project) {
    // TODO: Navigate to SessionPickerPage (Phase 03)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Session picker coming soon (Phase 03)'),
        backgroundColor: CatppuccinMocha.yellow,
      ),
    );
  }
}
