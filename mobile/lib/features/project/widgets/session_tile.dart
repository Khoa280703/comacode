import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/models.dart';

/// Single session item tile
class SessionTile extends StatelessWidget {
  final SessionMetadata session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const SessionTile({
    required this.session,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CatppuccinMocha.surface0,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Terminal icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CatppuccinMocha.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.terminal,
                  color: CatppuccinMocha.green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // Session info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: CatppuccinMocha.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatCreatedAt(session.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: CatppuccinMocha.overlay1,
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron
              Icon(
                Icons.chevron_right,
                color: CatppuccinMocha.subtext0,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCreatedAt(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dateTime.month}/${dateTime.day}';
  }
}
