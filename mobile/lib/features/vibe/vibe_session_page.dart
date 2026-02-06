import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme.dart';
import '../../bridge/bridge_wrapper.dart';
import '../connection/connection_providers.dart';
import '../project/models/project.dart';
import '../project/models/session_metadata.dart';
import 'models/vibe_session_state.dart';
import 'vibe_session_providers.dart';
import 'widgets/quick_keys_toolbar.dart';
import 'widgets/output_view.dart';
import 'widgets/search_overlay.dart';
import 'widgets/session_tab_bar.dart';
import '../terminal/ssh_input_handler.dart'; // SSH Terminal Mode - Phase 1
import '../terminal/prediction_engine.dart'; // SSH Terminal Mode - Phase 2
import 'services/light_session_storage.dart'; // Terminal history persistence

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

class _VibeSessionPageState extends ConsumerState<VibeSessionPage>
    with WidgetsBindingObserver {
  bool _showSearch = false;
  final FocusNode _keyboardFocusNode = FocusNode();

  // Phase 02: Terminal resize tracking
  Timer? _resizeTimer;
  int? _cachedCols;
  int? _cachedRows;
  int? _lastSentCols;
  int? _lastSentRows;
  Terminal? _resizeCallbackTerminal; // tracks which Terminal instance has onResize set

  // SSH Terminal Mode - Phase 1: Terminal input handler
  // Captures ALL keystrokes via HardwareKeyboard and sends via KeyBatch
  SshInputHandler? _terminalInputHandler;

  // SSH Terminal Mode - Phase 2: Prediction engine for speculative local echo
  PredictionEngine? _predictionEngine;
  Timer? _ackPollTimer;

  // Terminal history persistence
  final LightSessionStorage _storage = LightSessionStorage();

  // Cached notifier reference for safe dispose (ref unavailable after dispose)
  VibeSessionNotifier? _vibeNotifier;

  @override
  void initState() {
    super.initState();
    // Add lifecycle observer for flush on pause
    WidgetsBinding.instance.addObserver(this);

    if (widget.project != null && widget.session != null) {
      final sessionId = widget.session!.id;
      final vibeNotifier = ref.read(vibeSessionProvider.notifier);

      // Cache for safe dispose (ref unavailable after widget disposed)
      _vibeNotifier = vibeNotifier;

      // Initialize storage (wires onOutput callback)
      _initStorage(sessionId);

      // Check if event loop already running for this session
      // (navigate back → tap lại → initState chạy lại nhưng PTY vẫn alive)
      if (vibeNotifier.isAttachedTo(sessionId)) {
        debugPrint('[VibeSession] Already attached to $sessionId, skipping create');
        // Restore persisted size
        final size = vibeNotifier.getLastSentSize(sessionId);
        if (size != null) {
          _cachedCols = size[0];
          _cachedRows = size[1];
          _lastSentCols = size[0];
          _lastSentRows = size[1];
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _keyboardFocusNode.requestFocus();
            _initTerminalInputHandler();
          }
        });
      } else {
        // Not attached → need to create/attach session
        // This handles: first entry, flutter restart, session switch
        _initializeSessionWithRetry().then((_) {
          if (mounted) {
            _initTerminalInputHandler();
          }
        });
      }
    } else {
      // Direct connection mode
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _keyboardFocusNode.requestFocus();
          _initTerminalInputHandler();
        }
      });
    }
  }

  /// Initialize storage and restore history from file
  Future<void> _initStorage(String sessionId) async {
    await _storage.init(sessionId);

    // Wire output callback to persist new terminal output
    ref.read(vibeSessionProvider.notifier).onOutput = (data) {
      _storage.append(data);
    };

    // Only load history if terminal is empty (first entry or after clear)
    // Skip if terminal already has data from cache (re-entry case)
    final vibeState = ref.read(vibeSessionProvider);
    final vibeNotifier = ref.read(vibeSessionProvider.notifier);

    // Check if this is a fresh session (no cached terminal data)
    if (!vibeNotifier.hasSession(sessionId)) {
      // Load history into terminal (instant first paint via streaming)
      await for (final chunk in _storage.load()) {
        vibeState.terminal.write(chunk);
      }
      debugPrint('[VibeSession] Storage loaded history for new session $sessionId');
    } else {
      debugPrint('[VibeSession] Storage skipped load - terminal already has data for $sessionId');
    }
  }

  /// Handle app lifecycle changes - flush storage on pause
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _storage.flushOnPause();
    }
  }

  /// Initialize SSH terminal input handler
  void _initTerminalInputHandler() {
    // CRITICAL FIX: Don't create multiple handlers on re-entry
    // Multiple handlers = duplicate keystrokes (aaa instead of a)
    if (_terminalInputHandler != null) {
      debugPrint('[VibeSession] Input handler already exists, skipping init');
      return;
    }

    final vibeState = ref.read(vibeSessionProvider);
    final bridge = ref.read(bridgeWrapperProvider);

    // Create prediction engine (Phase 2)
    _predictionEngine = PredictionEngine(
      terminal: vibeState.terminal,
      onLatencyUpdate: (rtt) {
        debugPrint('[SSH Terminal Mode] RTT: ${rtt.inMilliseconds}ms');
      },
    );

    // Create input handler with prediction
    // No textFieldFocusNode - all input goes directly to terminal
    _terminalInputHandler = SshInputHandler(
      terminal: vibeState.terminal,
      onKeyBatch: (bytes, seq) {
        bridge.sendKeyBatch(keys: bytes, sequenceNum: seq).catchError((e) {
          debugPrint('[SSH Terminal Mode] sendKeyBatch error: $e');
        });
      },
      // textFieldFocusNode: null - Pure SSH mode, direct terminal input
    );
    _terminalInputHandler!.attachWithPrediction(_predictionEngine!);

    // Start polling for KeyBatchAck (Phase 2)
    _startAckPolling(bridge);
  }

  /// Start polling for KeyBatchAck messages
  void _startAckPolling(BridgeWrapper bridge) {
    _ackPollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!mounted) return;
      final seq = await bridge.pollKeyBatchAck();
      if (seq > 0) {
        _predictionEngine?.handleAck(seq);
      }
    });
  }

  @override
  void dispose() {
    // CRITICAL: Detach input handler FIRST to prevent duplicate handlers
    // HardwareKeyboard.instance is global - handlers accumulate if not removed
    _terminalInputHandler?.detach();
    _terminalInputHandler = null;

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Dispose storage (flushes pending data)
    _storage.dispose();

    // Clear output callback using cached ref (ref unavailable after dispose)
    _vibeNotifier?.onOutput = null;
    _vibeNotifier = null;

    _ackPollTimer?.cancel();
    _ackPollTimer = null;
    _predictionEngine?.dispose();
    _predictionEngine = null;
    _keyboardFocusNode.dispose();
    _resizeTimer?.cancel();
    super.dispose();
  }

  /// Called after onResize fires (size guaranteed valid).
  /// Sends resize → createSession → attachSession in order.
  Future<void> _initializeSessionWithRetry() async {
    try {
      final sessionId = widget.session!.id;
      final projectPath = widget.project!.path;
      final vibeNotifier = ref.read(vibeSessionProvider.notifier);
      final bridge = ref.read(bridgeWrapperProvider);

      // Resize BEFORE createSession → server stores as pending_resize
      // → PTY spawns with this exact size → 0 extra SIGWINCH on first prompt
      if (_cachedCols != null && _cachedRows != null) {
        await bridge.resizePty(rows: _cachedRows!, cols: _cachedCols!);
        _lastSentCols = _cachedCols;
        _lastSentRows = _cachedRows;
        vibeNotifier.updateLastSentSize(sessionId, _cachedCols!, _cachedRows!);
      }

      await bridge.createSession(
        projectPath: projectPath,
        sessionId: sessionId,
      );

      await vibeNotifier.attachSession(sessionId);
    } catch (e) {
      debugPrint('[VibeSession] Session init failed: $e');
    }
  }

  /// Phase 02: Setup terminal resize callback
  ///
  /// Called once when terminal is available. Handles:
  /// - Time A: onResize from xterm (first mount + screen rotation)
  /// - Time B: on connection established (sync cached size)
  void _setupResizeCallback(Terminal terminal, WidgetRef ref) {
    _resizeCallbackTerminal = terminal;

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
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
        // Persist to provider so re-entry can restore without sending resize
        ref.read(vibeSessionProvider.notifier).updateLastSentSize(widget.session?.id ?? '', cols, rows);
        debugPrint('[VibeSession] Terminal resized: ${cols}x$rows');
      } catch (e) {
        debugPrint('[VibeSession] Resize failed: $e');
      }
    });
  }

  // _onConnectionEstablished removed: resize is now handled exclusively by
  // _initializeSessionWithRetry (first load) and _debouncedResize (subsequent)

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final vibeState = ref.watch(vibeSessionProvider);

    // Setup resize callback synchronously — MUST be before layout phase
    // so that onResize fires with callback already set (triggers deferred createSession).
    // Re-set when terminal changes (e.g., after attachSession switches to different session's Terminal)
    if (_resizeCallbackTerminal != vibeState.terminal) {
      _setupResizeCallback(vibeState.terminal, ref);
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
                _storage.clear(); // Clear persisted history too
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
    // SSH Terminal Mode - Phase Fix-04: Remove old keyboard handler
    // SshInputHandler now captures ALL keyboard events via HardwareKeyboard
    // No need for Focus.onKeyEvent (it was blocking Enter key)
    return Focus(
      focusNode: _keyboardFocusNode,
      // onKeyEvent removed - SshInputHandler handles all keys directly
      child: Stack(
        children: [
        Column(
          children: [
            // Tab bar for multi-session (Phase 02)
            const SessionTabBar(),
            // Output display
            Expanded(
              child: OutputView(
                terminal: vibeState.terminal,
                isParsedMode: false,
              ),
            ),
            // Quick keys toolbar only (SSH Terminal Mode - direct input)
            QuickKeysToolbar(
              onKeyPressed: (key) =>
                  ref.read(vibeSessionProvider.notifier).sendSpecialKey(key),
            ),
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

