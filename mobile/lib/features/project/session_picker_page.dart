import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../connection/connection_providers.dart';
import '../vibe/vibe_session_page.dart';
import 'models/models.dart';
import 'project_providers.dart';
import 'widgets/session_list.dart';

/// Session Picker Screen
///
/// Phase 03: Project & Session Management
/// Shows recent sessions + option to create new one
class SessionPickerPage extends ConsumerStatefulWidget {
  final Project project;

  const SessionPickerPage({
    required this.project,
    super.key,
  });

  @override
  ConsumerState<SessionPickerPage> createState() => _SessionPickerPageState();
}

class _SessionPickerPageState extends ConsumerState<SessionPickerPage> {
  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final fingerprint = connectionState.currentHost?.fingerprint ?? '';

    // FIX: Watch provider để get fresh project data (không dùng stale widget.project)
    // Khi backend tạo session mới, provider update → widget rebuild → show latest sessions
    final projects = ref.watch(projectNotifierProvider(fingerprint));
    final freshProject = projects.firstWhere(
      (p) => p.id == widget.project.id,
      orElse: () => widget.project,
    );

    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Session', style: TextStyle(fontSize: 18)),
            Text(
              freshProject.name,
              style: TextStyle(
                fontSize: 12,
                color: CatppuccinMocha.subtext0,
              ),
            ),
          ],
        ),
        backgroundColor: CatppuccinMocha.mantle,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _createNewSession(context, fingerprint),
            tooltip: 'New Session',
          ),
        ],
      ),
      body: SessionList(
        project: freshProject,
        onSessionTap: (session) => _startSession(context, session),
        onDelete: (session) => _handleDeleteSession(context, fingerprint, session),
      ),
    );
  }

  void _createNewSession(BuildContext context, String fingerprint) {
    // Use freshProject for current session count
    final freshProject = ref.read(projectNotifierProvider(fingerprint));
    final currentProject = freshProject.firstWhere(
      (p) => p.id == widget.project.id,
      orElse: () => widget.project,
    );
    final defaultName = 'Session ${currentProject.sessions.length + 1}';
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final nameController = TextEditingController(text: defaultName);

          return AlertDialog(
            backgroundColor: CatppuccinMocha.surface,
            title: Text(
              'New Session',
              style: TextStyle(color: CatppuccinMocha.text),
            ),
            content: TextField(
              controller: nameController,
              style: TextStyle(color: CatppuccinMocha.text),
              decoration: InputDecoration(
                labelText: 'Session Name',
                labelStyle: TextStyle(color: CatppuccinMocha.subtext0),
                hintStyle: TextStyle(color: CatppuccinMocha.overlay0),
                filled: true,
                fillColor: CatppuccinMocha.surface0,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: isCreating
                    ? null
                    : () => Navigator.pop(dialogContext),
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

                        // Validate session name
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a session name'),
                              backgroundColor: CatppuccinMocha.red,
                            ),
                          );
                          return;
                        }

                        if (!_isValidSessionName(name)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Invalid name. Use letters, numbers, -, _ only (max 50 chars)',
                              ),
                              backgroundColor: CatppuccinMocha.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isCreating = true);

                        final session = SessionMetadata.create(name: name);

                        await ref
                            .read(projectNotifierProvider(fingerprint).notifier)
                            .addSession(widget.project.id, session);

                        // Clean up controller
                        nameController.dispose();

                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          _startSession(context, session);
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
          );
        },
      ),
    );
  }

  bool _isValidSessionName(String name) {
    // Allow letters, numbers, hyphen, underscore; max 50 chars
    if (name.length > 50) return false;
    final validPattern = RegExp(r'^[a-zA-Z0-9_\-\s]+$');
    return validPattern.hasMatch(name);
  }

  void _startSession(BuildContext context, SessionMetadata session) {
    // Phase 05: Navigate to VibeSessionPage with project + session context
    // FIX: Use push() instead of pushReplacement() to keep SessionPickerPage in stack
    // This allows proper back navigation from VibeSessionPage → SessionPickerPage
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VibeSessionPage(
          project: widget.project,
          session: session,
        ),
      ),
    );
  }

  void _handleDeleteSession(
    BuildContext context,
    String fingerprint,
    SessionMetadata session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Delete Session',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Text(
          'Delete "${session.name}"?',
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
          .removeSession(widget.project.id, session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session "${session.name}" deleted'),
            backgroundColor: CatppuccinMocha.green,
          ),
        );
      }
    }
  }
}
