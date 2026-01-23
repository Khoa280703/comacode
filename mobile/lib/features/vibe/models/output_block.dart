/// Output block types for parsed terminal output
enum BlockType {
  /// Raw text (fallback for unrecognized patterns)
  raw,

  /// File path: lib/.../file.dart
  file,

  /// Git diff: + added, - removed
  diff,

  /// List items: - item, * item
  list,

  /// Plan steps: 1. Step one
  plan,

  /// Error message
  error,

  /// Question prompt: (Y/n), (y/N)
  question,

  /// Code block: ```lang ... ```
  code,

  /// Tool use: running command, reading file
  tool,
}

/// Parsed output block for enhanced display
class OutputBlock {
  final BlockType type;
  final String content;
  final List<OutputBlock>? children;
  bool isCollapsed;
  final Map<String, String>? metadata;

  OutputBlock({
    required this.type,
    required this.content,
    this.children,
    this.isCollapsed = false,
    this.metadata,
  });

  OutputBlock copyWith({
    BlockType? type,
    String? content,
    List<OutputBlock>? children,
    bool? isCollapsed,
    Map<String, String>? metadata,
  }) {
    return OutputBlock(
      type: type ?? this.type,
      content: content ?? this.content,
      children: children ?? this.children,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Check if block has collapsible content
  bool get isCollapsible => children != null && children!.isNotEmpty;

  /// Check if block is a diff line
  bool get isDiffAdded => type == BlockType.diff && content.startsWith('+');
  bool get isDiffRemoved => type == BlockType.diff && content.startsWith('-');

  /// Get file path if this is a file block
  String? get filePath {
    if (type == BlockType.file) {
      return content.trim();
    }
    return metadata?['path'];
  }

  /// Get question options if this is a question block
  List<String>? get questionOptions {
    if (type == BlockType.question && metadata != null) {
      final opts = metadata!['options'];
      if (opts != null) return opts.split(',');
    }
    return null;
  }
}
