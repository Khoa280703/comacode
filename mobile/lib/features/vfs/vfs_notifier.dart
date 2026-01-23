import 'dart:async';
import 'package:flutter/foundation.dart';
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
/// Phase VFS-Fix: Stream now emits single chunk with all data (no race condition)
class VfsNotifier extends StateNotifier<VfsState> {
  final BridgeWrapper _bridge;
  StreamSubscription<List<VfsEntry>>? _dirSubscription;

  VfsNotifier(this._bridge) : super(VfsState.initial());

  /// Load directory entries from server using Stream API
  ///
  /// Phase VFS-Fix: Stream emits single chunk with all entries.
  /// Rust side collects all data before sending → no race condition.
  Future<void> loadDirectory(String path) async {
    // Cancel old stream
    await _dirSubscription?.cancel();
    _dirSubscription = null;

    // Update path and loading state
    state = state.copyWith(
      currentPath: path,
      isLoading: true,
      error: null,
      entries: [],  // Clear old entries while loading
    );

    try {
      // Stream-based directory listing
      // Rust now waits for ALL data before emitting single chunk
      _dirSubscription = _bridge.listDirectory(path).listen(
        // onData: Single chunk with all entries
        (entries) {
          debugPrint('📦 [VfsNotifier] RAW entries: ${entries.length}');

          // CRITICAL: Create NEW list to avoid mutating original
          // Also sort safely
          final sortedEntries = List<VfsEntry>.from(entries);
          sortedEntries.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.compareTo(b.name);
          });

          // CRITICAL: Set ALL fields explicitly to avoid any issues
          final newState = VfsState(
            currentPath: path,
            entries: sortedEntries,
            isLoading: false,
            hasMore: false,
            error: null,
          );

          state = newState;
          debugPrint('✅ [VfsNotifier] Updated state: path=$path, entries=${sortedEntries.length}, isLoading=false');
        },
        // onError
        onError: (error) {
          state = state.copyWith(
            isLoading: false,
            error: error.toString(),
          );
          debugPrint('❌ [VfsNotifier] Stream error: $error');
        },
        // onDone
        onDone: () {
          // Phase VFS-Fix: Do NOT modify state here!
          // onData already set isLoading=false and entries
          // onDone fires after, so we should not overwrite anything
          debugPrint('✅ [VfsNotifier] Stream done (state has ${state.entries.length} entries)');
        },
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

  /// Refresh current directory (cancel + restart)
  void refresh() {
    loadDirectory(state.currentPath);
  }

  /// Clear error state
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  @override
  void dispose() {
    // Cancel stream to prevent memory leak
    _dirSubscription?.cancel();
    super.dispose();
  }
}

/// Riverpod provider for VFS state
final vfsProvider = StateNotifierProvider<VfsNotifier, VfsState>((ref) {
  final bridge = ref.watch(bridgeWrapperProvider);
  return VfsNotifier(bridge);
});
