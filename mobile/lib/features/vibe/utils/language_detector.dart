/// Detect highlight.js language from file extension
String detectLanguage(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'dart' => 'dart',
    'js' || 'mjs' => 'javascript',
    'jsx' => 'javascript',
    'ts' => 'typescript',
    'tsx' => 'javascript',
    'py' || 'pyw' => 'python',
    'rs' => 'rust',
    'go' => 'go',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'swift' => 'swift',
    'c' || 'h' => 'c',
    'cpp' || 'cc' || 'cxx' || 'hpp' => 'cpp',
    'cs' => 'csharp',
    'rb' => 'ruby',
    'php' => 'php',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'toml' => 'ini',
    'md' || 'markdown' => 'markdown',
    'html' || 'htm' => 'html',
    'css' => 'css',
    'scss' || 'sass' => 'scss',
    'sql' => 'sql',
    'sh' || 'bash' || 'zsh' => 'bash',
    'xml' => 'xml',
    'dockerfile' => 'dockerfile',
    'makefile' => 'makefile',
    _ => 'plaintext',
  };
}

/// Fallback grammar when primary grammar fails (returns <=1 node on large files).
/// Dart port of highlight.js has broken grammars for some languages at scale.
String? detectLanguageFallback(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'cpp' || 'cc' || 'cxx' || 'hpp' => 'objectivec',
    'cs' => 'swift',
    'kt' || 'kts' => 'scala',
    _ => null,
  };
}

/// Check if file is likely binary based on extension
bool isLikelyBinary(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const binaryExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'zip', 'tar', 'gz', 'rar', '7z', 'bz2',
    'exe', 'dll', 'so', 'dylib', 'bin',
    'mp3', 'mp4', 'avi', 'mov', 'wav', 'flac',
    'ttf', 'otf', 'woff', 'woff2', 'eot',
    'sqlite', 'db',
  };
  return binaryExtensions.contains(ext);
}

/// Check if file is a supported image format (viewable as image)
/// Images are binary but can be displayed inline
bool isImageFile(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const imageExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
  };
  return imageExtensions.contains(ext);
}

/// Check if file is an SVG image (vector, text-based XML)
bool isSvgFile(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return ext == 'svg';
}

/// Check if file is a Markdown document
bool isMarkdownFile(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return ext == 'md' || ext == 'markdown';
}

/// Check if file is an HTML document
bool isHtmlFile(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return ext == 'html' || ext == 'htm';
}
