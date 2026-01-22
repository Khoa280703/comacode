import 'package:flutter/material.dart';
import '../../../../core/theme.dart';
import '../../../models/dir_entry.dart';

/// File/folder entry tile for VFS browser
///
/// Phase VFS-2: UI component for directory entries
class EntryTile extends StatelessWidget {
  final VfsEntry entry;
  final VoidCallback onTap;

  const EntryTile({
    super.key,
    required this.entry,
    required this.onTap,
  });

  bool get _isDir => entry.isDir;

  String get _name => entry.name;

  String? _formattedSize() {
    return entry.formattedSize;
  }

  @override
  Widget build(BuildContext context) {
    final isDir = _isDir;
    final name = _name;

    return ListTile(
      leading: Icon(
        isDir ? Icons.folder : Icons.insert_drive_file_outlined,
        color: isDir
            ? CatppuccinMocha.yellow
            : CatppuccinMocha.blue,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: CatppuccinMocha.text,
          fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      subtitle: isDir
          ? null
          : Text(
              _formattedSize() ?? '',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 12,
              ),
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: CatppuccinMocha.overlay0,
      ),
      onTap: onTap,
    );
  }
}
