import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../models/dir_entry.dart';
import '../../vfs/vfs_notifier.dart';

/// File explorer view for Vibe session
///
/// Displays directory tree from VFS, allows navigation and file selection
class FileExplorerView extends ConsumerStatefulWidget {
  /// Callback when file is tapped
  final void Function(String path, String name)? onFileTap;

  /// Initial path to load (project root)
  final String initialPath;

  const FileExplorerView({
    super.key,
    this.onFileTap,
    this.initialPath = '.',
  });

  @override
  ConsumerState<FileExplorerView> createState() => _FileExplorerViewState();
}

class _FileExplorerViewState extends ConsumerState<FileExplorerView> {
  @override
  void initState() {
    super.initState();
    // Load initial directory
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vfsProvider.notifier).loadDirectory(widget.initialPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vfsState = ref.watch(vfsProvider);

    return Column(
      children: [
        // Breadcrumb / Path bar
        _buildPathBar(vfsState),

        // File list
        Expanded(
          child: vfsState.isLoading
              ? _buildLoadingShimmer()
              : vfsState.error != null
                  ? _buildError(vfsState.error!)
                  : _buildFileList(vfsState),
        ),
      ],
    );
  }

  Widget _buildPathBar(VfsState state) {
    // Don't allow navigating outside project root
    final canGoUp = !state.isAtRoot &&
        state.currentPath.startsWith(widget.initialPath) &&
        state.currentPath != widget.initialPath;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: CatppuccinMocha.surface0,
      child: Row(
        children: [
          // Back button - only show if can go up within project
          if (canGoUp)
            IconButton(
              icon: Icon(Icons.arrow_back, color: CatppuccinMocha.text),
              onPressed: () => ref.read(vfsProvider.notifier).navigateUp(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 8),
          // Path display
          Expanded(
            child: Text(
              state.currentPath,
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh, color: CatppuccinMocha.text),
            onPressed: () => ref.read(vfsProvider.notifier).refresh(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(VfsState state) {
    if (state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: CatppuccinMocha.subtext0),
            const SizedBox(height: 16),
            Text(
              'Empty directory',
              style: TextStyle(color: CatppuccinMocha.subtext0),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(vfsProvider.notifier).refresh();
        // Wait for loading to complete
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        itemCount: state.entries.length,
        itemBuilder: (context, index) {
          final entry = state.entries[index];
          return _buildEntryTile(entry);
        },
      ),
    );
  }

  Widget _buildEntryTile(VfsEntry entry) {
    final icon = entry.isDir ? Icons.folder : _getFileIcon(entry.name);
    final color = entry.isDir ? CatppuccinMocha.yellow : CatppuccinMocha.text;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        entry.name,
        style: TextStyle(
          color: CatppuccinMocha.text,
          fontFamily: 'monospace',
        ),
      ),
      trailing: entry.isDir
          ? Icon(Icons.chevron_right, color: CatppuccinMocha.subtext0)
          : _buildFileSize(entry.size),
      onTap: () {
        if (entry.isDir) {
          ref.read(vfsProvider.notifier).navigateDown(entry.path);
        } else {
          widget.onFileTap?.call(entry.path, entry.name);
        }
      },
    );
  }

  Widget? _buildFileSize(int? size) {
    if (size == null) return null;
    final sizeStr = _formatSize(size);
    return Text(
      sizeStr,
      style: TextStyle(
        color: CatppuccinMocha.subtext0,
        fontSize: 12,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.flutter_dash,
      'js' || 'jsx' => Icons.javascript,
      'ts' || 'tsx' => Icons.code,
      'py' => Icons.code,
      'rs' => Icons.memory,
      'go' => Icons.code,
      'java' || 'kt' => Icons.android,
      'swift' => Icons.apple,
      'json' => Icons.data_object,
      'yaml' || 'yml' => Icons.settings,
      'md' => Icons.article,
      'html' || 'css' => Icons.web,
      'sh' || 'bash' => Icons.terminal,
      'txt' => Icons.text_snippet,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => Icons.image,
      'pdf' => Icons.picture_as_pdf,
      'lock' => Icons.lock,
      _ => Icons.insert_drive_file,
    };
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: CatppuccinMocha.red, size: 48),
          const SizedBox(height: 16),
          Text(
            error,
            style: TextStyle(color: CatppuccinMocha.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.read(vfsProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Loading shimmer placeholder while fetching directory
  Widget _buildLoadingShimmer() {
    return ListView.builder(
      itemCount: 8,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icon placeholder
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: CatppuccinMocha.surface1,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 16),
            // Text placeholder - varying widths for realism
            Expanded(
              child: Container(
                height: 16,
                width: (index % 3 + 1) * 60.0,
                decoration: BoxDecoration(
                  color: CatppuccinMocha.surface1,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
