import '../bridge/ffi_helpers.dart';

/// Directory entry for VFS browsing
///
/// Phase VFS-2: Flutter UI for file system browser
class VfsEntry {
  final String name;
  final String path;
  final bool isDir;
  final bool isSymlink;
  final int? size;
  final int? modified;
  final String? permissions;

  VfsEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isSymlink = false,
    this.size,
    this.modified,
    this.permissions,
  });

  /// Create VfsEntry from FFI-generated DirEntry
  factory VfsEntry.fromFrb(DirEntry frbEntry) {
    // Parse FFI response using helper functions
    return VfsEntry(
      name: getDirEntryName(frbEntry),
      path: getDirEntryPath(frbEntry),
      isDir: isDirEntryDir(frbEntry),
      isSymlink: isDirEntrySymlink(frbEntry),
      size: getDirEntrySize(frbEntry),
      modified: getDirEntryModified(frbEntry),
      permissions: getDirEntryPermissions(frbEntry),
    );
  }

  /// Format file size for display (KB, MB, GB)
  String get formattedSize {
    if (size == null) return '';
    final bytes = size!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get formatted modified time
  String get formattedModified {
    if (modified == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(modified! * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'VfsEntry(name: $name, path: $path, isDir: $isDir)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VfsEntry &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          path == other.path;

  @override
  int get hashCode => name.hashCode ^ path.hashCode;
}
