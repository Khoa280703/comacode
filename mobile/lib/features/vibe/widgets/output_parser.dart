import '../models/output_block.dart';

/// Output parser for enhanced terminal display
///
/// Uses heuristic patterns to detect:
/// - File paths
/// - Git diffs
/// - Questions/prompts
/// - Lists
/// - Plans
/// - Code blocks
/// - Tool use sections
class OutputParser {
  /// Regex patterns for detection
  static final RegExp _filePattern = RegExp(
    r'[\w\-./]+/[\w\-./]*\.(\w+|Dockerfile|Makefile|Containerfile|gitignore)$',
    caseSensitive: false,
  );

  static final RegExp _questionPattern = RegExp(
    r'\([Yy]/[Nn]\)|\([Nn]/[Yy]\)|\(yes/no\)|\(y/n\)',
  );

  static final RegExp _planStepPattern = RegExp(
    r'^\s*(\d+\.|[a-zA-Z]\.)\s+',
    multiLine: true,
  );

  static final RegExp _listPattern = RegExp(
    r'^\s*[\-\*+]\s+',
    multiLine: true,
  );

  static final RegExp _codeBlockPattern = RegExp(
    r'```[\w\+]*\n([\s\S]*?)\n```',
    multiLine: true,
  );

  static final RegExp _toolPattern = RegExp(
    r'^(Running|Reading|Writing|Executing|Searching)\s+',
    caseSensitive: false,
  );

  /// Parse terminal output into structured blocks
  static List<OutputBlock> parse(String output) {
    if (output.isEmpty) return [];

    final blocks = <OutputBlock>[];
    final lines = output.split('\n');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final block = _parseLine(line, lines, i);
      blocks.add(block);
      i += _countLinesConsumed(block);
    }

    return _mergeConsecutiveBlocks(blocks);
  }

  /// Parse single line with context
  static OutputBlock _parseLine(
    String line,
    List<String> lines,
    int currentIndex,
  ) {
    // Tool use section
    if (_toolPattern.hasMatch(line)) {
      return OutputBlock(
        type: BlockType.tool,
        content: line,
        metadata: {'tool': line.split(' ').first},
      );
    }

    // Question prompt
    final questionMatch = _questionPattern.firstMatch(line);
    if (questionMatch != null) {
      return OutputBlock(
        type: BlockType.question,
        content: line,
        metadata: {'options': _extractOptions(questionMatch.group(0)!)},
      );
    }

    // Diff line
    if (line.startsWith('+++ ') || line.startsWith('--- ') ||
        line.startsWith('+') && !line.startsWith('++') ||
        line.startsWith('-') && !line.startsWith('---')) {
      return OutputBlock(
        type: BlockType.diff,
        content: line,
      );
    }

    // Plan step
    if (_planStepPattern.hasMatch(line)) {
      return OutputBlock(
        type: BlockType.plan,
        content: line,
        children: _extractPlanChildren(lines, currentIndex),
      );
    }

    // List item
    if (_listPattern.hasMatch(line)) {
      return OutputBlock(
        type: BlockType.list,
        content: line,
      );
    }

    // File path
    final fileMatch = _filePattern.firstMatch(line);
    if (fileMatch != null) {
      return OutputBlock(
        type: BlockType.file,
        content: fileMatch.group(0)!,
        metadata: {'fullLine': line},
      );
    }

    // Code block
    final codeMatch = _codeBlockPattern.firstMatch(line);
    if (codeMatch != null) {
      return OutputBlock(
        type: BlockType.code,
        content: codeMatch.group(1) ?? '',
      );
    }

    // Error detection
    if (_isErrorLine(line)) {
      return OutputBlock(
        type: BlockType.error,
        content: line,
      );
    }

    // Default: raw text
    return OutputBlock(
      type: BlockType.raw,
      content: line,
    );
  }

  /// Extract children for plan blocks (indented content)
  static List<OutputBlock>? _extractPlanChildren(List<String> lines, int startIndex) {
    final children = <OutputBlock>[];
    int i = startIndex + 1;

    // Collect indented lines until next non-indented
    while (i < lines.length) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('   ') || line.startsWith('\t')) {
        children.add(OutputBlock(
          type: BlockType.raw,
          content: line,
        ));
        i++;
      } else {
        break;
      }
    }

    return children.isEmpty ? null : children;
  }

  /// Extract options from question prompt
  static String _extractOptions(String prompt) {
    if (prompt.contains('(Y/n)')) return 'Y,n';
    if (prompt.contains('(y/N)')) return 'y,N';
    if (prompt.contains('(y/n)')) return 'y,n';
    if (prompt.contains('(Y/N)')) return 'Y,N';
    return 'yes,no';
  }

  /// Extract options from question prompt
  static String extractOptions(String prompt) {
    return _extractOptions(prompt);
  }

  /// Check if line is an error
  static bool _isErrorLine(String line) {
    final lower = line.toLowerCase();
    final errorIndicators = [
      'error:', 'exception:', 'failed', 'cannot', 'unable to',
      'warning:', 'warn:', 'not found', 'no such file', 'undefined',
    ];
    return errorIndicators.any((ind) => lower.contains(ind));
  }

  /// Count how many lines a block consumes (for children)
  static int _countLinesConsumed(OutputBlock block) {
    if (block.isCollapsible && block.isCollapsed) {
      return 1;
    }
    return 1 + (block.children?.length ?? 0);
  }

  /// Merge consecutive blocks of same type
  static List<OutputBlock> _mergeConsecutiveBlocks(List<OutputBlock> blocks) {
    if (blocks.isEmpty) return blocks;

    final merged = <OutputBlock>[blocks.first];

    for (int i = 1; i < blocks.length; i++) {
      final current = blocks[i];
      final last = merged.last;

      // Only merge raw blocks
      if (last.type == BlockType.raw && current.type == BlockType.raw) {
        merged[merged.length - 1] = OutputBlock(
          type: BlockType.raw,
          content: '${last.content}\n${current.content}',
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  /// Extract all file paths from output
  static List<String> extractFilePaths(String output) {
    final matches = _filePattern.allMatches(output);
    return matches.map((m) => m.group(0)!).toList();
  }

  /// Extract all diff hunks from output
  static List<String> extractDiffHunks(String output) {
    final lines = output.split('\n');
    final hunks = <String>[];
    final currentHunk = <String>[];
    bool inDiff = false;

    for (final line in lines) {
      if (line.startsWith('@@ ')) {
        inDiff = true;
        if (currentHunk.isNotEmpty) {
          hunks.add(currentHunk.join('\n'));
          currentHunk.clear();
        }
        currentHunk.add(line);
      } else if (inDiff) {
        if (line.startsWith('+') || line.startsWith('-') ||
            line.startsWith(' ') || line.isEmpty) {
          currentHunk.add(line);
        } else {
          inDiff = false;
          if (currentHunk.isNotEmpty) {
            hunks.add(currentHunk.join('\n'));
            currentHunk.clear();
          }
        }
      }
    }

    if (currentHunk.isNotEmpty) {
      hunks.add(currentHunk.join('\n'));
    }

    return hunks;
  }

  /// Check if output contains a question prompt
  static bool hasQuestionPrompt(String output) {
    return _questionPattern.hasMatch(output);
  }

  /// Get the active question prompt from output
  static String? getQuestionPrompt(String output) {
    final match = _questionPattern.firstMatch(output);
    return match?.group(0);
  }
}
