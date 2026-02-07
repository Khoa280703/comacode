import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme.dart';
import '../../bridge/bridge_wrapper.dart';
import '../connection/connection_providers.dart';
import '../project/models/project.dart';
import '../project/models/session_metadata.dart';
import 'models/vibe_session_state.dart';
import 'models/view_mode.dart';
import 'vibe_session_providers.dart';
import 'widgets/quick_keys_toolbar.dart';
import 'widgets/output_view.dart';
import 'widgets/search_overlay.dart';
import 'widgets/session_tab_bar.dart';
import 'widgets/file_explorer_view.dart';
import 'utils/language_detector.dart'; // for isImageFile, isSvgFile, isMarkdownFile, isHtmlFile
import 'utils/markdown_theme.dart'; // Catppuccin Markdown theme
import 'utils/catppuccin_highlight_theme.dart'; // Catppuccin syntax highlight theme
import 'widgets/html_viewer.dart'; // Safe HTML viewer
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
  // Cached sessionId for unregistering output callback in dispose
  String? _registeredSessionId;

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
        // Initialize storage (just wire callback, history already in terminal cache)
        _initStorage(sessionId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _keyboardFocusNode.requestFocus();
            _initTerminalInputHandler();
          }
        });
      } else {
        // Not attached → need to create/attach session
        // CRITICAL: Load history BEFORE starting event loop to prevent race condition
        // History must be in terminal BEFORE new PTY output arrives
        _initStorageThenSession(sessionId);
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

    // Wire output callback to persist new terminal output (per-session)
    // CRITICAL: Use per-session callback to prevent history cross-contamination
    _registeredSessionId = sessionId;
    ref.read(vibeSessionProvider.notifier).registerOutputCallback(sessionId, (data) {
      _storage.append(data);
    });

    final vibeNotifier = ref.read(vibeSessionProvider.notifier);

    // Check if this is a fresh session (no cached terminal data)
    if (!vibeNotifier.hasSession(sessionId)) {
      // CRITICAL: Get the CORRECT terminal for this session BEFORE loading history
      // This ensures history goes into the right terminal, not the current one
      final sessionTerminal = vibeNotifier.getTerminalForSession(sessionId);

      // Load history into session's terminal (instant first paint via streaming)
      await for (final chunk in _storage.load()) {
        sessionTerminal.write(chunk);
      }
      debugPrint('[VibeSession] Storage loaded history for new session $sessionId');
    } else {
      debugPrint('[VibeSession] Storage skipped load - terminal already has data for $sessionId');
    }
  }

  /// Initialize storage THEN session - ensures history loads before event loop starts
  /// This prevents race condition where new PTY output overwrites history
  Future<void> _initStorageThenSession(String sessionId) async {
    // Step 1: Load history into terminal FIRST
    await _initStorage(sessionId);

    // Step 2: THEN start session (which starts event loop)
    // New output will append AFTER history
    await _initializeSessionWithRetry();

    if (mounted) {
      _initTerminalInputHandler();
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

    // Unregister output callback using cached ref (ref unavailable after dispose)
    if (_registeredSessionId != null) {
      _vibeNotifier?.unregisterOutputCallback(_registeredSessionId!);
    }
    _registeredSessionId = null;
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

  /// Show file picker bottom sheet with directory tree navigation
  void _showFilePickerBottomSheet(BuildContext context) {
    // Use last browsed path if available, otherwise start from project root
    final vibeState = ref.read(vibeSessionProvider);
    final projectRoot = widget.project?.path ?? '.';
    final initialPath = vibeState.lastBrowsedPath ?? projectRoot;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CatppuccinMocha.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CatppuccinMocha.overlay0,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.folder_open, color: CatppuccinMocha.mauve),
                  const SizedBox(width: 12),
                  Text(
                    'Select File',
                    style: TextStyle(
                      color: CatppuccinMocha.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: CatppuccinMocha.subtext0),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // File tree
            Expanded(
              child: FileExplorerView(
                initialPath: initialPath,
                rootPath: projectRoot,
                onFileTap: (path, name) {
                  // Close bottom sheet and open file in content area
                  Navigator.pop(ctx);
                  ref.read(vibeSessionProvider.notifier).openFile(path, name);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          // View mode toggle (File Viewer Feature)
          if (connectionState.isConnected)
            SegmentedButton<ViewMode>(
              segments: const [
                ButtonSegment(
                  value: ViewMode.terminal,
                  icon: Icon(Icons.terminal, size: 16),
                ),
                ButtonSegment(
                  value: ViewMode.files,
                  icon: Icon(Icons.folder_outlined, size: 16),
                ),
              ],
              selected: {vibeState.viewMode},
              onSelectionChanged: (selected) {
                final newMode = selected.first;
                ref.read(vibeSessionProvider.notifier).setViewMode(newMode);
                // Hide keyboard when switching to Files mode
                if (newMode == ViewMode.files) {
                  FocusScope.of(context).unfocus();
                }
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          const SizedBox(width: 8),
          // Connection status indicator
          _ConnectionStatusBadge(state: connectionState),
          const SizedBox(width: 8),
          // Search button (Phase 02) - only in terminal mode
          if (connectionState.isConnected && vibeState.viewMode == ViewMode.terminal)
            IconButton(
              icon: Icon(Icons.search, color: CatppuccinMocha.text),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                });
              },
              tooltip: 'Search in output',
            ),
          // Browse files button - only in files mode
          if (connectionState.isConnected && vibeState.viewMode == ViewMode.files)
            IconButton(
              icon: Icon(Icons.folder_open, color: CatppuccinMocha.mauve),
              onPressed: () => _showFilePickerBottomSheet(context),
              tooltip: 'Browse files',
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
            // Main content - IndexedStack keeps both mounted but only shows active one
            // NOTE: AnimatedCrossFade caused render tree crashes when VFS state updates
            // during cross-fade animation. IndexedStack is simpler and more stable.
            Expanded(
              child: IndexedStack(
                index: vibeState.viewMode == ViewMode.terminal ? 0 : 1,
                children: [
                  OutputView(
                    terminal: vibeState.terminal,
                    isParsedMode: false,
                  ),
                  // Files mode: Show opened file content or "No file open" placeholder
                  _buildFilesView(vibeState),
                ],
              ),
            ),
            // Quick keys toolbar only in terminal mode
            if (vibeState.viewMode == ViewMode.terminal)
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

  /// Build the files view content area
  /// Shows "No file open" placeholder or the opened file content
  Widget _buildFilesView(VibeSessionState vibeState) {
    if (!vibeState.hasOpenedFile) {
      // No file open - show placeholder with hint to use browse button
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: CatppuccinMocha.overlay0,
            ),
            const SizedBox(height: 16),
            Text(
              'No file open',
              style: TextStyle(
                color: CatppuccinMocha.subtext0,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the folder icon to browse files',
              style: TextStyle(
                color: CatppuccinMocha.overlay0,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // File is open - show FileViewerPage inline (without AppBar)
    return _InlineFileViewer(
      key: ValueKey(vibeState.openedFilePath),
      filePath: vibeState.openedFilePath!,
      fileName: vibeState.openedFileName!,
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

/// Inline file viewer widget (used in Files mode content area)
/// Shows file content with syntax highlighting and minimal file info
class _InlineFileViewer extends ConsumerStatefulWidget {
  final String filePath;
  final String fileName;

  const _InlineFileViewer({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  ConsumerState<_InlineFileViewer> createState() => _InlineFileViewerState();
}

class _InlineFileViewerState extends ConsumerState<_InlineFileViewer> {
  bool _isLoading = true;
  String? _content;
  Uint8List? _imageBytes; // For image files (base64 decoded)
  String? _error;
  bool _truncated = false;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant _InlineFileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _loadFile();
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _content = null;
      _imageBytes = null;
    });

    try {
      final bridge = ref.read(bridgeWrapperProvider);
      final result = await bridge.readFile(widget.filePath);

      if (result == null) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load file';
        });
        return;
      }

      // Check if this is an image file
      if (isImageFile(widget.fileName)) {
        // Backend returns base64 encoded image data
        try {
          final bytes = base64Decode(result.content);
          setState(() {
            _isLoading = false;
            _imageBytes = bytes;
            _truncated = result.truncated;
            _size = result.size.toInt();
          });
        } catch (e) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to decode image';
          });
        }
        return;
      }

      // Text file
      setState(() {
        _isLoading = false;
        _content = result.content;
        _truncated = result.truncated;
        _size = result.size.toInt();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Minimal file info bar - compact breadcrumb style
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: CatppuccinMocha.mantle,
          child: Row(
            children: [
              Icon(
                isImageFile(widget.fileName) ? Icons.image
                  : isSvgFile(widget.fileName) ? Icons.image_outlined
                  : isMarkdownFile(widget.fileName) ? Icons.article_outlined
                  : isHtmlFile(widget.fileName) ? Icons.language
                  : Icons.code,
                color: CatppuccinMocha.mauve,
                size: 14,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.fileName,
                  style: TextStyle(
                    color: CatppuccinMocha.subtext1,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_size > 0) ...[
                Text(
                  ' · ',
                  style: TextStyle(color: CatppuccinMocha.overlay0, fontSize: 12),
                ),
                Text(
                  _formatSize(_size),
                  style: TextStyle(
                    color: CatppuccinMocha.overlay0,
                    fontSize: 11,
                  ),
                ),
              ],
              if (_truncated) ...[
                const SizedBox(width: 8),
                Icon(Icons.warning_amber_rounded, color: CatppuccinMocha.yellow, size: 14),
              ],
            ],
          ),
        ),
        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: CatppuccinMocha.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: CatppuccinMocha.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Image display with zoom/pan
    if (_imageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            _imageBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: CatppuccinMocha.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to display image',
                    style: TextStyle(color: CatppuccinMocha.red),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    // SVG display with zoom/pan
    if (isSvgFile(widget.fileName) && _content != null) {
      try {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: SvgPicture.string(
              _content!,
              fit: BoxFit.contain,
              placeholderBuilder: (context) => const CircularProgressIndicator(),
            ),
          ),
        );
      } catch (e) {
        // Fallback to raw text if SVG parsing fails
      }
    }

    // Markdown rendering with Catppuccin theme
    if (isMarkdownFile(widget.fileName) && _content != null) {
      return Markdown(
        data: _content!,
        styleSheet: catppuccinMarkdownTheme(context),
        selectable: true,
        onTapLink: (text, href, title) {
          if (href != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Link: $href')),
            );
          }
        },
      );
    }

    // HTML rendering with safe viewer
    if (isHtmlFile(widget.fileName) && _content != null) {
      return SafeHtmlViewer(htmlContent: _content!);
    }

    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(
          'Empty file',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
      );
    }

    // Syntax highlighting for code files
    final language = detectLanguage(widget.fileName);

    // Hybrid Strategy:
    // - File < 50KB: Full-file highlight with SingleChildScrollView
    // - File > 50KB: Plain text with ListView.builder (performance)
    final isLargeFile = _content!.length > 50 * 1024;

    if (isLargeFile) {
      // Large file: Plain text with virtual scroll (no highlight)
      final lines = _content!.split('\n');
      return ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line number gutter
              Container(
                width: 50,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                color: CatppuccinMocha.mantle,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: CatppuccinMocha.overlay0,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              // Plain text (no highlight for large files)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    lines[index].isEmpty ? ' ' : lines[index],
                    style: TextStyle(
                      color: CatppuccinMocha.text,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // Small file (< 50KB): Full-file highlight + line numbers
    final lines = _content!.split('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line number gutter
            Container(
              color: CatppuccinMocha.mantle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(lines.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: CatppuccinMocha.overlay0,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Full content with syntax highlighting
            HighlightView(
              _content!,
              language: language,
              theme: catppuccinMochaTheme,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
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

