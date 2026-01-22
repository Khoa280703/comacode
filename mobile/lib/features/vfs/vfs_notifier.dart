import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bridge/bridge_wrapper.dart';
import '../../../models/dir_entry.dart';

/// VFS state for directory browsing
class VfsState {
  final String currentPath;
  final List<VfsEntry> entries;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const VfsState({
    required this.currentPath,
    this.entries = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.error,
  });

  /// Initial state (root directory)
  factory VfsState.initial() {
    return VfsState(
      currentPath: '/',
      entries: [],
      isLoading: false,
    );
  }

  /// Copy with for immutable state updates
  VfsState copyWith({
    String? currentPath,
    List<VfsEntry>? entries,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return VfsState(
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error ?? this.error,
    );
  }

  /// Check if at root directory
  bool get isAtRoot => currentPath == '/' || currentPath == '.' || currentPath.isEmpty;

  /// Get parent path
  String get parentPath {
    if (isAtRoot) return currentPath;
    final parts = currentPath.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.length <= 1) return '/';
    parts.removeLast();
    return '/${parts.join('/')}';
  }

  /// Get display name (basename of current path)
  String get displayName {
    if (isAtRoot) return '/';
    final parts = currentPath.split('/')..removeWhere((p) => p.isEmpty);
    return parts.last;
  }
}

/// VFS Notifier for directory browsing
///
/// Phase VFS-2: State management for file browser
class VfsNotifier extends StateNotifier<VfsState> {
  final BridgeWrapper _bridge;

  VfsNotifier(this._bridge) : super(VfsState.initial());

  /// Load directory entries from server
  Future<void> loadDirectory(String path) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final entries = await _bridge.listDirectory(path);
      state = VfsState(
        currentPath: path,
        entries: entries,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Navigate to parent directory
  void navigateUp() {
    if (state.isAtRoot) return;
    final parent = state.parentPath;
    loadDirectory(parent);
  }

  /// Navigate into child directory
  void navigateDown(String childPath) {
    loadDirectory(childPath);
  }

  /// Refresh current directory
  void refresh() {
    loadDirectory(state.currentPath);
  }

  /// Clear error state
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }
}

/// Riverpod provider for VFS state
final vfsProvider = StateNotifierProvider<VfsNotifier, VfsState>((ref) {
  final bridge = ref.watch(bridgeWrapperProvider);
  return VfsNotifier(bridge);
});
