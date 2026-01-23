import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../vfs/vfs_notifier.dart';
import '../../vfs/widgets/entry_tile.dart';

/// VFS File Picker for project directory selection
///
/// Phase 02: Project & Session Management
/// Returns selected directory path to caller
class VfsFilePicker extends ConsumerWidget {
  const VfsFilePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vfsState = ref.watch(vfsProvider);
    final notifier = ref.read(vfsProvider.notifier);

    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Directory'),
            Text(
              vfsState.currentPath,
              style: TextStyle(
                fontSize: 12,
                color: CatppuccinMocha.subtext0,
              ),
            ),
          ],
        ),
        backgroundColor: CatppuccinMocha.mantle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (vfsState.isAtRoot) {
              Navigator.pop(context);
            } else {
              notifier.navigateUp();
            }
          },
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Select'),
            onPressed: () => Navigator.pop(context, vfsState.currentPath),
          ),
        ],
      ),
      body: vfsState.isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : vfsState.error != null
              ? Center(
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
                        'Error loading directory',
                        style: TextStyle(
                          color: CatppuccinMocha.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        vfsState.error!,
                        style: TextStyle(
                          color: CatppuccinMocha.subtext0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: () => notifier.refresh(),
                      ),
                    ],
                  ),
                )
              : vfsState.entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 48,
                            color: CatppuccinMocha.overlay1,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Empty directory',
                            style: TextStyle(
                              color: CatppuccinMocha.subtext0,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: vfsState.entries.length,
                      itemBuilder: (context, index) {
                        final entry = vfsState.entries[index];
                        return EntryTile(
                          key: ValueKey(entry.path),
                          entry: entry,
                          onTap: () {
                            if (entry.isDir) {
                              notifier.navigateDown(entry.path);
                            }
                          },
                        );
                      },
                    ),
    );
  }
}
