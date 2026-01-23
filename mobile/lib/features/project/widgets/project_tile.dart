import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/models.dart';

/// Single project item tile
class ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ProjectTile({
    required this.project,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CatppuccinMocha.surface0,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Folder icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CatppuccinMocha.mauve.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.folder,
                  color: CatppuccinMocha.mauve,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Project info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: CatppuccinMocha.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      project.path,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CatppuccinMocha.subtext0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.layers,
                          size: 12,
                          color: CatppuccinMocha.overlay1,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${project.sessions.length} session${project.sessions.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CatppuccinMocha.overlay1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: CatppuccinMocha.overlay1,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatLastAccessed(project.lastAccessed),
                          style: const TextStyle(
                            fontSize: 11,
                            color: CatppuccinMocha.overlay1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(
                Icons.chevron_right,
                color: CatppuccinMocha.subtext0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastAccessed(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}';
  }
}
