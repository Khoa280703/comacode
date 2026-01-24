import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/models.dart';
import 'session_tile.dart';

/// List of sessions within a project
class SessionList extends StatelessWidget {
  final Project project;
  final Function(SessionMetadata) onSessionTap;
  final Function(SessionMetadata) onDelete;

  const SessionList({
    required this.project,
    required this.onSessionTap,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (project.sessions.isEmpty) {
      return _EmptyState(project: project);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: project.sessions.length,
      itemBuilder: (context, index) {
        final session = project.sessions[index];
        return SessionTile(
          session: session,
          onTap: () => onSessionTap(session),
          onDelete: () => onDelete(session),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Project project;

  const _EmptyState({required this.project});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 64,
            color: CatppuccinMocha.overlay1,
          ),
          const SizedBox(height: 16),
          Text(
            'No sessions yet',
            style: TextStyle(
              fontSize: 18,
              color: CatppuccinMocha.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new session to start coding',
            style: TextStyle(
              color: CatppuccinMocha.subtext0,
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.add_circle_outline,
            size: 24,
            color: CatppuccinMocha.green,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create a session',
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
