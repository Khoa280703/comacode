import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bridge/bridge_wrapper.dart';
import '../../../core/theme.dart';
import '../utils/language_detector.dart';
import '../utils/catppuccin_highlight_theme.dart';

/// LRU Cache for file content (5 files max)
/// Prevents re-fetching when user navigates back to previously viewed files
class _FileCache {
  static const int maxSize = 5;
  static final Map<String, _CachedFile> _cache = {};
  static final List<String> _accessOrder = [];

  static _CachedFile? get(String path) {
    if (_cache.containsKey(path)) {
      // Move to end (most recently accessed)
      _accessOrder.remove(path);
      _accessOrder.add(path);
      return _cache[path];
    }
    return null;
  }

  static void put(String path, _CachedFile file) {
    // Evict oldest if at capacity
    while (_cache.length >= maxSize && _accessOrder.isNotEmpty) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[path] = file;
    _accessOrder.add(path);
  }
}

class _CachedFile {
  final String content;
  final bool truncated;
  final int size;
  _CachedFile({required this.content, required this.truncated, required this.size});
}

/// File viewer page with syntax highlighting
class FileViewerPage extends ConsumerStatefulWidget {
  final String filePath;
  final String fileName;

  const FileViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  ConsumerState<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends ConsumerState<FileViewerPage> {
  bool _isLoading = true;
  String? _content;
  String? _error;
  bool _truncated = false;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    // Check for binary file
    if (isLikelyBinary(widget.fileName)) {
      setState(() {
        _isLoading = false;
        _error = 'Binary file - cannot display content';
      });
      return;
    }

    // Check LRU cache first
    final cached = _FileCache.get(widget.filePath);
    if (cached != null) {
      setState(() {
        _isLoading = false;
        _content = cached.content;
        _truncated = cached.truncated;
        _size = cached.size;
      });
      return;
    }

    try {
      final bridge = ref.read(bridgeWrapperProvider);
      final result = await bridge.readFile(widget.filePath);

      if (result == null) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load file (timeout)';
        });
        return;
      }

      // Check for binary content (null bytes)
      if (_containsBinaryData(result.content)) {
        setState(() {
          _isLoading = false;
          _error = 'Binary file - cannot display content';
        });
        return;
      }

      // Save to LRU cache
      _FileCache.put(widget.filePath, _CachedFile(
        content: result.content,
        truncated: result.truncated,
        size: result.size.toInt(),
      ));

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

  bool _containsBinaryData(String content) {
    if (content.isEmpty) return false;

    // Check first 1000 bytes for binary markers
    final bytes = content.codeUnits.take(1000).toList();
    int nullBytes = 0;
    int controlChars = 0;

    for (final b in bytes) {
      if (b == 0) nullBytes++;
      // Control chars except tab (0x09), newline (0x0A), carriage return (0x0D)
      if (b < 8 || (b >= 14 && b < 32)) controlChars++;
    }

    // Binary if >1% null bytes or >5% control chars
    final nullRatio = nullBytes / bytes.length;
    final controlRatio = controlChars / bytes.length;

    return nullRatio > 0.01 || controlRatio > 0.05;
  }

  /// Reload file content (clears cache for this file)
  Future<void> _reloadFile() async {
    // Clear from cache to force fresh load
    _FileCache._cache.remove(widget.filePath);
    _FileCache._accessOrder.remove(widget.filePath);

    setState(() {
      _isLoading = true;
      _error = null;
      _content = null;
    });

    await _loadFile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CatppuccinMocha.base,
      appBar: AppBar(
        backgroundColor: CatppuccinMocha.mantle,
        title: Text(
          widget.fileName,
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: CatppuccinMocha.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // File info
          if (_size > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _formatSize(_size),
                  style: TextStyle(
                    color: CatppuccinMocha.subtext0,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh, color: CatppuccinMocha.text),
            onPressed: _isLoading ? null : _reloadFile,
            tooltip: 'Reload file',
          ),
        ],
      ),
      body: Column(
        children: [
          // Truncation warning
          if (_truncated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: CatppuccinMocha.yellow.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Icon(Icons.warning, color: CatppuccinMocha.yellow, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'File truncated (exceeds 1MB limit)',
                    style: TextStyle(color: CatppuccinMocha.yellow, fontSize: 12),
                  ),
                ],
              ),
            ),
          // Content area
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
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

    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(
          'Empty file',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
      );
    }

    final language = detectLanguage(widget.fileName);

    // Hybrid Strategy (from review-plan.md):
    // - File < 50KB: Full-file highlight with SingleChildScrollView
    // - File > 50KB: Plain text with ListView.builder (no highlight)
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
