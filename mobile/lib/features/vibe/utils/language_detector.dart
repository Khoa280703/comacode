/// Detect highlight.js language from file extension
String detectLanguage(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'dart' => 'dart',
    'js' || 'jsx' || 'mjs' => 'javascript',
    'ts' || 'tsx' => 'typescript',
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

/// Check if file is likely binary based on extension
bool isLikelyBinary(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const binaryExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'zip', 'tar', 'gz', 'rar', '7z', 'bz2',
    'exe', 'dll', 'so', 'dylib', 'bin',
    'mp3', 'mp4', 'avi', 'mov', 'wav', 'flac',
    'ttf', 'otf', 'woff', 'woff2', 'eot',
    'sqlite', 'db',
  };
  return binaryExtensions.contains(ext);
}
