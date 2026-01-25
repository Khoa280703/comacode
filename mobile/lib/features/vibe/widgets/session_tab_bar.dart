import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../services/session_manager.dart';
import 'tab_item.dart';

/// Session tab bar for multi-session navigation
///
/// Phase 02: Multi-Session Tab Architecture
/// Shows all active sessions with horizontal scrolling
class SessionTabBar extends ConsumerWidget {
  const SessionTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionManagerProvider);
    final sessions = sessionState.sessionList;
    final activeId = sessionState.activeSessionId;

    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: CatppuccinMocha.mantle,
        border: Border(
          bottom: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = session.id == activeId;

                return TabItem(
                  session: session,
                  isActive: isActive,
                  onTap: () async {
                    // Phase 05: Async switch session
                    await ref.read(sessionManagerProvider.notifier).switchSession(session.id);
                  },
                  onLongPress: () => _showSessionMenu(context, ref, session),
                );
              },
            ),
          ),
          // New session button
          _NewSessionButton(
            onPressed: sessions.length >= 5
                ? null
                : () => _showNewSessionDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showSessionMenu(BuildContext context, WidgetRef ref, dynamic session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CatppuccinMocha.surface,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: CatppuccinMocha.text),
              title: Text(
                'Rename',
                style: TextStyle(color: CatppuccinMocha.text),
              ),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref, session);
              },
            ),
            ListTile(
              leading: Icon(Icons.close, color: CatppuccinMocha.red),
              title: Text(
                'Close Session',
                style: TextStyle(color: CatppuccinMocha.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _showCloseDialog(context, ref, session);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, dynamic session) {
    final controller = TextEditingController(text: session.projectName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Rename Session',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: CatppuccinMocha.text),
          decoration: InputDecoration(
            hintText: 'Session name',
            hintStyle: TextStyle(color: CatppuccinMocha.overlay1),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: CatppuccinMocha.surface1),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(sessionManagerProvider.notifier)
                    .renameSession(session.id, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text(
              'Rename',
              style: TextStyle(color: CatppuccinMocha.mauve),
            ),
          ),
        ],
      ),
    );
  }

  void _showCloseDialog(BuildContext context, WidgetRef ref, dynamic session) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Close Session',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Text(
          'Close "${session.projectName}" session? Claude may be working on tasks.',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Phase 05: Async close session
              await ref.read(sessionManagerProvider.notifier).closeSession(session.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(
              'Close',
              style: TextStyle(color: CatppuccinMocha.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showNewSessionDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final pathController = TextEditingController(text: '~/dev/');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'New Session',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: CatppuccinMocha.text),
              decoration: InputDecoration(
                labelText: 'Project Name',
                hintText: 'e.g., api, mobile, web',
                hintStyle: TextStyle(color: CatppuccinMocha.overlay1),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: CatppuccinMocha.surface1),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pathController,
              style: TextStyle(color: CatppuccinMocha.text),
              decoration: InputDecoration(
                labelText: 'Project Path',
                hintStyle: TextStyle(color: CatppuccinMocha.overlay1),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: CatppuccinMocha.surface1),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final path = pathController.text.trim();
              if (name.isNotEmpty && path.isNotEmpty) {
                final success = await ref
                    .read(sessionManagerProvider.notifier)
                    .createSession(projectPath: path, projectName: name);
                if (context.mounted) {
                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Max sessions reached'),
                        backgroundColor: CatppuccinMocha.red,
                      ),
                    );
                  }
                  Navigator.pop(context);
                }
              }
            },
            child: Text(
              'Create',
              style: TextStyle(color: CatppuccinMocha.mauve),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewSessionButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _NewSessionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(right: 8),
      child: IconButton(
        icon: Icon(Icons.add, size: 18),
        padding: const EdgeInsets.all(4),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: onPressed != null
              ? CatppuccinMocha.mauve.withValues(alpha: 0.2)
              : CatppuccinMocha.surface0,
          foregroundColor: onPressed != null
              ? CatppuccinMocha.mauve
              : CatppuccinMocha.overlay1,
        ),
        tooltip: 'New Session',
      ),
    );
  }
}
