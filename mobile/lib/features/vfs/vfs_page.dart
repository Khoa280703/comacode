import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../connection/connection_providers.dart';
import 'vfs_notifier.dart';
import 'widgets/entry_tile.dart';

/// VFS Browser page for directory navigation
///
/// Phase VFS-2: Main UI for file system browsing
class VfsPage extends ConsumerStatefulWidget {
  const VfsPage({super.key});

  @override
  ConsumerState<VfsPage> createState() => _VfsPageState();
}

class _VfsPageState extends ConsumerState<VfsPage> {
  @override
  void initState() {
    super.initState();
    // Load root directory on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vfsProvider.notifier).loadDirectory('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final vfsState = ref.watch(vfsProvider);

    // Auto-refresh when error occurs and connected
    ref.listen<VfsState>(vfsProvider, (previous, next) {
      if (next.error != null && connectionState.isConnected) {
        // Auto-clear error after delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            ref.read(vfsProvider.notifier).clearError();
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        backgroundColor: CatppuccinMocha.mantle,
        foregroundColor: CatppuccinMocha.text,
        title: Text(_getTitle(vfsState)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Phase VFS-Fix: Back button navigates to parent folder
            // Only exits when at root directory
            if (vfsState.isAtRoot) {
              Navigator.of(context).pop();
            } else {
              ref.read(vfsProvider.notifier).navigateUp();
            }
          },
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: vfsState.isLoading
                  ? CatppuccinMocha.overlay0
                  : CatppuccinMocha.text,
            ),
            onPressed: vfsState.isLoading
                ? null
                : () => ref.read(vfsProvider.notifier).refresh(),
          ),
          // Parent directory button (disabled at root)
          IconButton(
            icon: Icon(
              Icons.arrow_upward,
              color: vfsState.isAtRoot
                  ? CatppuccinMocha.overlay0
                  : CatppuccinMocha.text,
            ),
            onPressed: vfsState.isAtRoot
                ? null
                : () => ref.read(vfsProvider.notifier).navigateUp(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(vfsState, connectionState.isConnected),
    );
  }

  String _getTitle(VfsState state) {
    if (state.isLoading) return 'Loading...';
    return state.displayName;
  }

  Widget _buildBody(VfsState state, bool isConnected) {
    // Phase VFS-Fix: Debug log to diagnose empty directory issue
    debugPrint('🔍 [VfsPage] _buildBody: path=${state.currentPath}, isLoading=${state.isLoading}, entries=${state.entries.length}, error=${state.error}');

    if (!isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: CatppuccinMocha.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Not connected',
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to a terminal first',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Phase VFS-Fix: Check loading FIRST to prevent race condition
    // where loading=true but entries empty → shows "Empty" incorrectly
    if (state.isLoading) {
      // Show loading spinner even if entries exist (showing stale data during load)
      return const Center(
        child: CircularProgressIndicator(
          color: CatppuccinMocha.mauve,
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: CatppuccinMocha.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading directory',
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                state.error!,
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(vfsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CatppuccinMocha.mauve,
                foregroundColor: CatppuccinMocha.crust,
              ),
            ),
          ],
        ),
      );
    }

    if (state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: CatppuccinMocha.overlay0,
            ),
            const SizedBox(height: 16),
            Text(
              'Empty directory',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    // Directory listing with lazy loading
    return ListView.builder(
      itemCount: state.entries.length,
      itemBuilder: (context, index) {
        final entry = state.entries[index];
        return EntryTile(
          entry: entry,
          onTap: () {
            // Navigate into directory if it's a folder
            if (entry.isDir) {
              ref.read(vfsProvider.notifier).navigateDown(entry.path);
            }
          },
        );
      },
    );
  }
}
