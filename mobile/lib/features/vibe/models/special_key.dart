/// Special keys for terminal interaction
enum SpecialKey {
  arrowUp,
  arrowDown,
  enter,
  ctrlC,
}

extension SpecialKeyExtension on SpecialKey {
  String get sequence {
    switch (this) {
      case SpecialKey.arrowUp:
        return '\x1b[A';
      case SpecialKey.arrowDown:
        return '\x1b[B';
      case SpecialKey.enter:
        return '\r';
      case SpecialKey.ctrlC:
        return '\x03';
    }
  }

  String get label {
    switch (this) {
      case SpecialKey.arrowUp:
        return '↑';
      case SpecialKey.arrowDown:
        return '↓';
      case SpecialKey.enter:
        return 'Enter';
      case SpecialKey.ctrlC:
        return 'Ctrl+C';
    }
  }

  /// Get all special key values
  static List<SpecialKey> get values => [
    SpecialKey.arrowUp,
    SpecialKey.arrowDown,
    SpecialKey.enter,
    SpecialKey.ctrlC,
  ];
}
