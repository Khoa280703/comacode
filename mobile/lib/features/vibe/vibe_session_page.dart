import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme.dart';
import '../../bridge/bridge_wrapper.dart';
import '../connection/connection_providers.dart';
import '../project/models/project.dart';
import '../project/models/session_metadata.dart';
import 'models/special_key.dart';
import 'models/vibe_session_state.dart';
import 'vibe_session_providers.dart';
import 'widgets/input_bar.dart';
import 'widgets/output_view.dart';
import 'widgets/search_overlay.dart';
import 'widgets/session_tab_bar.dart';

/// Vibe Session Page - Chat-style interface for Claude Code CLI
///
/// Phase 01: Core Vibe UI (MVP)
/// - Chat-style output display with xterm
/// - Input bar with prompt field
/// - Quick keys toolbar
/// - Dual-mode toggle (Raw / Parsed)
///
/// Phase 02: Enhanced Features
/// - Enhanced output parsing (files, diffs, collapsible)
/// - Output search functionality
///
/// Phase 05: Multi-session support
/// - Accept optional Project and SessionMetadata context
/// - Re-attach/re-spawn logic for session restoration
class VibeSessionPage extends ConsumerStatefulWidget {
  /// Project context (optional - null for direct connection)
  final Project? project;

  /// Session metadata (optional - null for direct connection)
  final SessionMetadata? session;

  const VibeSessionPage({
    this.project,
    this.session,
    super.key,
  });

  @override
  ConsumerState<VibeSessionPage> createState() => _VibeSessionPageState();
}

class _VibeSessionPageState extends ConsumerState<VibeSessionPage> {
  bool _showSearch = false;
  bool _isRestoring = false;
  String? _restoreMessage;
  final FocusNode _keyboardFocusNode = FocusNode();

  // Phase 02: Terminal resize tracking
  Timer? _resizeTimer;
  int? _cachedCols;
  int? _cachedRows;
  int? _lastSentCols;
  int? _lastSentRows;
  bool _resizeCallbackSetup = false;

  @override
  void initState() {
    super.initState();
    // Phase 05: Initialize session with re-attach/re-spawn logic
    if (widget.project != null && widget.session != null) {
      _initializeSessionWithRetry();
    }
    // Auto-focus for physical keyboard support
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _resizeTimer?.cancel(); // Cancel pending resize timer
    super.dispose();
  }

  /// Handle physical keyboard events (Bluetooth/USB keyboards)
  KeyEventResult _handleKeyEvent(KeyEvent event, WidgetRef ref) {
    // Only handle key down events
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final modifiers = HardwareKeyboard.instance.logicalKeysPressed;

    // Check modifier state
    final isCtrl = modifiers.contains(LogicalKeyboardKey.controlLeft) ||
                   modifiers.contains(LogicalKeyboardKey.controlRight);
    final isAlt = modifiers.contains(LogicalKeyboardKey.altLeft) ||
                  modifiers.contains(LogicalKeyboardKey.altRight);

    // Handle Ctrl combinations
    if (isCtrl) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.ctrlC);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.ctrlD);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyL:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.ctrlL);
          return KeyEventResult.handled;
      }
    }

    // Handle special keys without Alt (Alt is often used for system shortcuts)
    if (!isAlt) {
      switch (key) {
        case LogicalKeyboardKey.tab:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.tab);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.arrowUp);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.arrowDown);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.arrowUp);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          ref.read(vibeSessionProvider.notifier).sendSpecialKey(SpecialKey.arrowDown);
          return KeyEventResult.handled;
      }
    }

    // Let TextField handle regular character input
    return KeyEventResult.ignored;
  }

  /// Initialize session with re-attach/re-spawn logic
  ///
  /// Phase 05: When app restarts, mobile has session metadata but server PTYs may be dead.
  /// Strategy:
  /// 1. Check if session exists on server
  /// 2. If exists → Re-attach (reuse existing PTY)
  /// 3. If not exists → Re-spawn (create new PTY with same config)
  Future<void> _initializeSessionWithRetry() async {
    setState(() => _isRestoring = true);

    try {
      final sessionId = widget.session!.id;
      final projectPath = widget.project!.path;
      final vibeNotifier = ref.read(vibeSessionProvider.notifier);

      setState(() => _restoreMessage = 'Attaching to session...');

      // Step 1: Check if session exists on server
      final bridge = ref.read(bridgeWrapperProvider);
      final exists = await bridge.checkSession(sessionId);

      if (exists) {
        // Re-attach: Server PTY still alive, just connect
        setState(() => _restoreMessage = 'Restoring session...');
        await _attachToExistingSession(sessionId);
      } else {
        // Re-spawn: Create new PTY with same config
        setState(() => _restoreMessage = 'Starting new session...');
        await bridge.createSession(
          projectPath: projectPath,
          sessionId: sessionId,
        );
      }

      // Step 2: Switch to this session on server
      // This tells the server to pump output for this session
      setState(() => _restoreMessage = 'Connecting...');
      await bridge.switchSession(sessionId);

      // Step 3: CRITICAL - Attach session to ensure event loop is running
      // This is now called every time we enter the session page
      // The attachSession() method is smart enough to handle re-entry properly
      await vibeNotifier.attachSession(sessionId);

      // Step 4: Send a test command to verify PTY is alive
      // This ensures we're connected to a working PTY
      // Empty command just pings the PTY without executing anything
      await bridge.sendCommand('\r'); // Send Enter to refresh prompt

      // Step 5: Clear restore message after delay
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _restoreMessage = null);
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() => _restoreMessage = 'Failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _attachToExistingSession(String sessionId) async {
    // Session exists on server, just attach to receive output
    // Event loop will be restarted via attachSession() after switchSession()
    debugPrint('📌 [VibeSession] Attaching to existing session: $sessionId');
  }

  /// Phase 02: Setup terminal resize callback
  ///
  /// Called once when terminal is available. Handles:
  /// - Time A: onResize from xterm (first mount + screen rotation)
  /// - Time B: on connection established (sync cached size)
  void _setupResizeCallback(Terminal terminal, WidgetRef ref) {
    if (_resizeCallbackSetup) return;
    _resizeCallbackSetup = true;

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      // width = cols, height = rows from xterm.dart
      _cachedCols = width;
      _cachedRows = height;

      final connectionState = ref.read(connectionStateProvider);
      if (connectionState.isConnected) {
        _debouncedResize(height, width);
      }
    };
  }

  /// Debounced resize to avoid PTY spam
  void _debouncedResize(int rows, int cols) {
    // Skip if same as last sent
    if (cols == _lastSentCols && rows == _lastSentRows) return;

    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final bridge = ref.read(bridgeWrapperProvider);
        await bridge.resizePty(rows: rows, cols: cols);
        _lastSentCols = cols;
        _lastSentRows = rows;
        debugPrint('✅ Terminal resized: ${cols}x$rows');
        
        // OPTIMIZATION: Let shell handle prompt naturally
        // No need to force clear screen - causes flickering
      } catch (e) {
        debugPrint('❌ Resize failed: $e');
      }
    });
  }

  /// Send cached size when connection is established
  ///
  /// OPTIMIZATION: Simplified init - no artificial delays or forced clears
  /// Backend now handles prompt trigger automatically after PTY spawn
  void _onConnectionEstablished(WidgetRef ref) {
    if (_cachedCols != null && _cachedRows != null) {
      // Send immediately without debounce for connection-time sync
      _resizeTimer?.cancel();
      Future.microtask(() async {
        try {
          final bridge = ref.read(bridgeWrapperProvider);
          await bridge.resizePty(rows: _cachedRows!, cols: _cachedCols!);
          _lastSentCols = _cachedCols;
          _lastSentRows = _cachedRows;
          debugPrint('✅ Initial terminal size: ${_cachedCols}x$_cachedRows');
          
          // Backend will trigger prompt automatically - no need to force it
        } catch (e) {
          debugPrint('❌ Initial resize failed: $e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final vibeState = ref.watch(vibeSessionProvider);

    // Setup resize callback on first build
    if (!_resizeCallbackSetup && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setupResizeCallback(vibeState.terminal, ref);
      });
    }

    // Handle connection-established resize (Time B)
    // Check if we just became connected and have cached size
    final wasConnected = _lastSentCols != null;
    if (connectionState.isConnected && !wasConnected && _cachedCols != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onConnectionEstablished(ref);
      });
    }

    // Phase 05: Show restoring state
    if (_isRestoring) {
      return Scaffold(
        backgroundColor: CatppuccinMocha.base,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: CatppuccinMocha.blue),
              const SizedBox(height: 16),
              Text(
                _restoreMessage ?? 'Restoring session...',
                style: TextStyle(
                  color: CatppuccinMocha.text,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        title: Text(
          connectionState.isConnected
              ? (widget.session?.name ?? 'Vibe Session')
              : 'Not Connected',
          style: TextStyle(
            color: CatppuccinMocha.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: CatppuccinMocha.mantle,
        elevation: 0,
        actions: [
          // Connection status indicator
          _ConnectionStatusBadge(state: connectionState),
          const SizedBox(width: 8),
          // Search button (Phase 02)
          if (connectionState.isConnected)
            IconButton(
              icon: Icon(Icons.search, color: CatppuccinMocha.text),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                });
              },
              tooltip: 'Search in output',
            ),
          const SizedBox(width: 4),
          // Mode toggle
          _ModeToggle(
            isRaw: vibeState.isOutputModeRaw,
            onTap: () =>
                ref.read(vibeSessionProvider.notifier).toggleOutputMode(),
          ),
          const SizedBox(width: 8),
          // Menu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: CatppuccinMocha.text),
            color: CatppuccinMocha.surface,
            onSelected: (value) {
              if (value == 'disconnect') {
                ref.read(connectionStateProvider.notifier).disconnect();
                if (context.mounted) {
                  // Phase 07: Navigate back to SessionPickerPage, not HomePage
                  // pop() once returns to SessionPickerPage (which is now kept in stack)
                  Navigator.of(context).pop();
                }
              } else if (value == 'clear') {
                vibeState.terminal.eraseDisplay();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear, color: CatppuccinMocha.text),
                  title: Text(
                    'Clear Terminal',
                    style: TextStyle(color: CatppuccinMocha.text),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'disconnect',
                child: ListTile(
                  leading: Icon(Icons.close, color: CatppuccinMocha.red),
                  title: Text(
                    'Disconnect',
                    style: TextStyle(color: CatppuccinMocha.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: connectionState.isConnected
          ? _buildConnected(context, ref, vibeState)
          : _buildDisconnected(context, connectionState),
    );
  }

  Widget _buildConnected(BuildContext context, WidgetRef ref,
      VibeSessionState vibeState) {
    return Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: (node, event) => _handleKeyEvent(event, ref),
      child: Stack(
        children: [
        Column(
          children: [
            // Tab bar for multi-session (Phase 02)
            const SessionTabBar(),
            // Output display (xterm or parsed)
            Expanded(
              child: vibeState.isOutputModeRaw
                  ? OutputView(
                      terminal: vibeState.terminal,
                      isParsedMode: false,
                    )
                  : _buildParsedOutput(context, ref, vibeState),
            ),
            // Input bar + Quick keys
            InputBar(),
            // Error banner
            if (vibeState.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: CatppuccinMocha.red.withValues(alpha: 0.2),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: CatppuccinMocha.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vibeState.error!,
                        style: TextStyle(color: CatppuccinMocha.red),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: CatppuccinMocha.red, size: 18),
                      onPressed: () =>
                          ref.read(vibeSessionProvider.notifier).clearError(),
                    ),
                  ],
                ),
              ),
          ],
        ),
        // Search overlay (Phase 02)
        if (_showSearch)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OutputSearchOverlay(
              output: '', // Terminal output is accessed via xterm
              terminal: vibeState.terminal,
              onClose: () {
                setState(() {
                  _showSearch = false;
                });
              },
            ),
          ),
      ],
    ),
    );
  }

  Widget _buildParsedOutput(BuildContext context, WidgetRef ref,
      VibeSessionState vibeState) {
    // For now, use xterm in parsed mode with highlighting enabled
    // Full parsed output view would require capturing terminal buffer
    return OutputView(
      terminal: vibeState.terminal,
      isParsedMode: true,
      onFileTap: () {
        // TODO: Navigate to VFS with file path
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File tap detected'),
            backgroundColor: CatppuccinMocha.blue,
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _buildDisconnected(BuildContext context, ConnectionModel state) {
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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              state.errorMessage ?? 'Please connect to a host first',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Go Back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CatppuccinMocha.mauve,
              foregroundColor: CatppuccinMocha.crust,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  final ConnectionModel state;

  const _ConnectionStatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state.status) {
      ConnectionStatus.connected => CatppuccinMocha.green,
      ConnectionStatus.connecting => CatppuccinMocha.yellow,
      ConnectionStatus.error => CatppuccinMocha.red,
      ConnectionStatus.disconnected => CatppuccinMocha.surface1,
    };

    final label = switch (state.status) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.connecting => 'Connecting...',
      ConnectionStatus.error => 'Error',
      ConnectionStatus.disconnected => 'Disconnected',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: CatppuccinMocha.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isRaw;
  final VoidCallback onTap;

  const _ModeToggle({
    required this.isRaw,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: CatppuccinMocha.surface0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: CatppuccinMocha.surface1,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRaw ? 'Raw' : 'Parsed',
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.swap_horiz,
              size: 16,
              color: CatppuccinMocha.overlay1,
            ),
          ],
        ),
      ),
    );
  }
}
