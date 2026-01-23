/// File attachment format for Vibe Coding prompts
enum AttachmentFormat {
  /// Path reference only: `Refactor @lib/models/user.dart`
  path,

  /// Full content: `Here's the file:\n\`\`\`dart\n{content}\n\`\`\``
  content,
}

extension AttachmentFormatExtension on AttachmentFormat {
  String get label {
    switch (this) {
      case AttachmentFormat.path:
        return 'Path only (@file)';
      case AttachmentFormat.content:
        return 'Full content';
    }
  }

  String formatAttachment(String path, String content) {
    switch (this) {
      case AttachmentFormat.path:
        return '@$path';
      case AttachmentFormat.content:
        return 'Here is `$path`:\n```\n$content\n```\n';
    }
  }
}
