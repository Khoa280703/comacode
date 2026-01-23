/// Bounded output buffer to prevent memory issues with large output
///
/// Limits buffer size by dropping oldest lines when exceeding MAX_LINES.
/// This prevents memory growth issues with long-running sessions.
class OutputBuffer {
  /// Maximum number of lines to keep in buffer
  static const int maxLines = 10000;

  /// Maximum size per line in bytes (to prevent single huge lines)
  static const int maxLineBytes = 4096;

  final List<String> _lines = [];
  int _totalBytes = 0;

  /// Current number of lines in buffer
  int get length => _lines.length;

  /// Whether buffer is at capacity
  bool get isFull => _lines.length >= maxLines;

  /// Whether buffer is empty
  bool get isEmpty => _lines.isEmpty;

  /// Get all lines currently in buffer
  List<String> get lines => List.unmodifiable(_lines);

  /// Add a line to buffer
  ///
  /// If buffer exceeds maxLines, oldest lines are dropped.
  /// If line exceeds maxLineBytes, it is truncated.
  void add(String line) {
    // Truncate huge lines
    final sanitized = _sanitizeLine(line);

    _lines.add(sanitized);
    _totalBytes += sanitized.length;

    // Drop oldest if over capacity
    while (_lines.length > maxLines) {
      final removed = _lines.removeAt(0);
      _totalBytes -= removed.length;
    }
  }

  /// Add multiple lines at once
  void addAll(List<String> lines) {
    for (final line in lines) {
      add(line);
    }
  }

  /// Clear all lines from buffer
  void clear() {
    _lines.clear();
    _totalBytes = 0;
  }

  /// Get a range of lines
  List<String> getRange(int start, int end) {
    if (start < 0) start = 0;
    if (end > _lines.length) end = _lines.length;
    if (start >= end) return [];

    return List.unmodifiable(_lines.sublist(start, end));
  }

  /// Get last N lines
  List<String> getLast(int count) {
    if (count <= 0) return [];
    if (count >= _lines.length) return List.unmodifiable(_lines);

    return List.unmodifiable(
      _lines.sublist(_lines.length - count),
    );
  }

  /// Approximate memory usage in bytes
  int get memoryUsage => _totalBytes;

  /// Sanitize a line to prevent buffer overflow issues
  String _sanitizeLine(String line) {
    // Truncate if too long
    if (line.length > maxLineBytes) {
      return '${line.substring(0, maxLineBytes)}\n<TRUNCATED>';
    }
    return line;
  }

  /// Convert buffer to single string
  @override
  String toString() {
    return _lines.join('\n');
  }

  /// Get buffer statistics
  Map<String, dynamic> get stats => {
        'lines': _lines.length,
        'maxLines': maxLines,
        'bytes': _totalBytes,
        'isFull': isFull,
      };
}
