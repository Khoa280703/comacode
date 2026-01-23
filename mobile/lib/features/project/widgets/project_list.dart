import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../models/models.dart';
import '../project_providers.dart';
import 'project_tile.dart';

/// List of projects for current connection
class ProjectList extends ConsumerWidget {
  const ProjectList({
    required this.fingerprint,
    required this.onProjectTap,
    super.key,
  });

  final String fingerprint;
  final Function(Project) onProjectTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider(fingerprint));

    return projectsAsync.when(
      data: (projects) {
        if (projects.isEmpty) {
          return const _EmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return ProjectTile(
              project: project,
              onTap: () => onProjectTap(project),
              onDelete: () => _handleDeleteProject(context, ref, project),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: CatppuccinMocha.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading projects',
              style: TextStyle(
                fontSize: 16,
                color: CatppuccinMocha.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _handleDeleteProject(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Delete Project',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Text(
          'Delete "${project.name}"? This will not delete files on disk.',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: CatppuccinMocha.subtext0),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: CatppuccinMocha.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(projectNotifierProvider(fingerprint).notifier)
          .deleteProject(project.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Project "${project.name}" deleted'),
            backgroundColor: CatppuccinMocha.green,
          ),
        );
      }
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: CatppuccinMocha.overlay1,
          ),
          const SizedBox(height: 16),
          Text(
            'No projects yet',
            style: TextStyle(
              fontSize: 18,
              color: CatppuccinMocha.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a project to start coding',
            style: TextStyle(
              color: CatppuccinMocha.subtext0,
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.arrow_upward,
            size: 24,
            color: CatppuccinMocha.mauve,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create a project',
            style: TextStyle(
              color: CatppuccinMocha.subtext0,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
