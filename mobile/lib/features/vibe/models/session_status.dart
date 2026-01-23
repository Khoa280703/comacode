/// Session status for Vibe Coding multi-session
///
/// Phase 02: Multi-Session Tab Architecture
enum SessionStatus {
  /// Currently viewing/active
  active,

  /// Running in background
  idle,

  /// Claude is processing
  busy,

  /// PTY died/corrupted
  error,
}

extension SessionStatusExtension on SessionStatus {
  String get label {
    switch (this) {
      case SessionStatus.active:
        return 'Active';
      case SessionStatus.idle:
        return 'Idle';
      case SessionStatus.busy:
        return 'Busy';
      case SessionStatus.error:
        return 'Error';
    }
  }

  /// Indicator color for UI
  String colorHex() {
    switch (this) {
      case SessionStatus.active:
        return '#89b4fa'; // CatppuccinMocha.blue
      case SessionStatus.idle:
        return '#a6adc8'; // CatppuccinMocha.overlay1
      case SessionStatus.busy:
        return '#f9e2af'; // CatppuccinMocha.yellow
      case SessionStatus.error:
        return '#f38ba8'; // CatppuccinMocha.red
    }
  }
}
