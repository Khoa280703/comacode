/// Special keys for terminal interaction
enum SpecialKey {
  arrowUp,
  arrowDown,
  enter,
  ctrlC,
  ctrlD,
  tab,
  ctrlL,
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
      case SpecialKey.ctrlD:
        return '\x04';
      case SpecialKey.tab:
        return '\t';
      case SpecialKey.ctrlL:
        return '\x0c';
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
      case SpecialKey.ctrlD:
        return 'Ctrl+D';
      case SpecialKey.tab:
        return 'Tab';
      case SpecialKey.ctrlL:
        return 'Clr';
    }
  }

  /// Get all special key values
  static List<SpecialKey> get values => [
    SpecialKey.arrowUp,
    SpecialKey.arrowDown,
    SpecialKey.enter,
    SpecialKey.tab,
    SpecialKey.ctrlD,
    SpecialKey.ctrlL,
    SpecialKey.ctrlC,
  ];
}
