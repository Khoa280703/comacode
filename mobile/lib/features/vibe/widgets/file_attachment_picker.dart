import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../vfs/vfs_notifier.dart';
import '../models/file_attachment.dart';

/// File attachment picker modal for Vibe Coding
///
/// Phase 02: File Attachment
/// - Multi-select files from VFS
/// - Choose attachment format (path/content)
class FileAttachmentPicker extends ConsumerStatefulWidget {
  final Function(List<String> paths, AttachmentFormat format) onFilesSelected;

  const FileAttachmentPicker({
    super.key,
    required this.onFilesSelected,
  });

  @override
  ConsumerState<FileAttachmentPicker> createState() =>
      _FileAttachmentPickerState();
}

class _FileAttachmentPickerState extends ConsumerState<FileAttachmentPicker> {
  final Set<String> _selectedPaths = {};
  AttachmentFormat _format = AttachmentFormat.path;

  @override
  void initState() {
    super.initState();
    // Load root directory on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vfsProvider.notifier).loadDirectory('/');
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _handleConfirm() {
    if (_selectedPaths.isEmpty) return;
    widget.onFilesSelected(_selectedPaths.toList(), _format);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vfsState = ref.watch(vfsProvider);

    return Dialog(
      backgroundColor: CatppuccinMocha.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(vfsState),
            // Format selector
            _buildFormatSelector(),
            // File list
            Expanded(
              child: _buildFileList(vfsState),
            ),
            // Footer with actions
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic vfsState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CatppuccinMocha.mantle,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file, color: CatppuccinMocha.mauve),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attach Files',
                  style: TextStyle(
                    color: CatppuccinMocha.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  vfsState.currentPath,
                  style: TextStyle(
                    color: CatppuccinMocha.subtext0,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Navigation buttons
          IconButton(
            icon: Icon(Icons.arrow_upward, color: CatppuccinMocha.text),
            onPressed: vfsState.isAtRoot
                ? null
                : () => ref.read(vfsProvider.notifier).navigateUp(),
            tooltip: 'Parent directory',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: CatppuccinMocha.text),
            onPressed:
                vfsState.isLoading ? null : () => ref.read(vfsProvider.notifier).refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Format:',
            style: TextStyle(color: CatppuccinMocha.subtext0, fontSize: 14),
          ),
          const SizedBox(width: 12),
          SegmentedButton<AttachmentFormat>(
            segments: AttachmentFormat.values.map((format) {
              return ButtonSegment(
                value: format,
                label: Text(format.label),
              );
            }).toList(),
            selected: {_format},
            onSelectionChanged: (Set<AttachmentFormat> selected) {
              setState(() => _format = selected.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return CatppuccinMocha.mauve;
                }
                return CatppuccinMocha.surface0;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return CatppuccinMocha.crust;
                }
                return CatppuccinMocha.text;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(dynamic vfsState) {
    if (vfsState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: CatppuccinMocha.mauve),
      );
    }

    if (vfsState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: CatppuccinMocha.red, size: 48),
            const SizedBox(height: 8),
            Text(
              vfsState.error!,
              style: TextStyle(color: CatppuccinMocha.red),
            ),
          ],
        ),
      );
    }

    if (vfsState.entries.isEmpty) {
      return Center(
        child: Text(
          'Empty directory',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
      );
    }

    return ListView.builder(
      itemCount: vfsState.entries.length,
      itemBuilder: (context, index) {
        final entry = vfsState.entries[index];
        final isSelected = _selectedPaths.contains(entry.path);
        final isSelectable = !entry.isDir; // Only files can be attached

        return CheckboxListTile(
          value: isSelected,
          onChanged: isSelectable ? (_) => _toggleSelection(entry.path) : null,
          enabled: isSelectable,
          title: Row(
            children: [
              Icon(
                entry.isDir ? Icons.folder : Icons.insert_drive_file,
                color: entry.isDir
                    ? CatppuccinMocha.yellow
                    : CatppuccinMocha.mauve,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    color: isSelectable
                        ? CatppuccinMocha.text
                        : CatppuccinMocha.overlay1,
                  ),
                ),
              ),
            ],
          ),
          subtitle: entry.isDir
              ? Text(
                  'Directory',
                  style: TextStyle(color: CatppuccinMocha.overlay1, fontSize: 12),
                )
              : null,
          checkboxShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CatppuccinMocha.mauve;
            }
            return CatppuccinMocha.surface0;
          }),
          checkColor: CatppuccinMocha.crust,
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_selectedPaths.length} file${_selectedPaths.length == 1 ? '' : 's'} selected',
            style: TextStyle(color: CatppuccinMocha.subtext0, fontSize: 14),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: CatppuccinMocha.subtext0),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedPaths.isEmpty ? null : _handleConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CatppuccinMocha.mauve,
                  foregroundColor: CatppuccinMocha.crust,
                  disabledBackgroundColor: CatppuccinMocha.surface0,
                  disabledForegroundColor: CatppuccinMocha.overlay1,
                ),
                child: Text('Attach ${_selectedPaths.isEmpty ? '' : '(${_selectedPaths.length})'}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Show file attachment picker modal
Future<void> showFileAttachmentPicker(
  BuildContext context, {
  required Function(List<String> paths, AttachmentFormat format) onFilesSelected,
}) {
  return showDialog(
    context: context,
    builder: (context) => FileAttachmentPicker(
      onFilesSelected: onFilesSelected,
    ),
  );
}
