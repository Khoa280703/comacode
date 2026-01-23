import 'package:haptic_feedback/haptic_feedback.dart';

/// Haptic feedback service for Vibe Coding
///
/// Provides typed haptic feedback methods for different interaction types.
/// Uses iOS Haptic Feedback API natively on supported devices.
class HapticService {
  HapticService._();

  /// Light haptic for subtle feedback
  /// Use for: file attached, small interactions
  static Future<void> light() async {
    try {
      await Haptics.vibrate(HapticsType.light);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Medium haptic for standard interactions
  /// Use for: send prompt, session switched
  static Future<void> medium() async {
    try {
      await Haptics.vibrate(HapticsType.medium);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Heavy haptic for important feedback
  /// Use for: errors, warnings
  static Future<void> heavy() async {
    try {
      await Haptics.vibrate(HapticsType.heavy);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Selection haptic for UI selection
  /// Use for: quick key press, toggle switches
  static Future<void> selection() async {
    try {
      await Haptics.vibrate(HapticsType.selection);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Success haptic for positive feedback
  /// Use for: operation completed successfully
  static Future<void> success() async {
    try {
      await Haptics.vibrate(HapticsType.success);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Warning haptic
  static Future<void> warning() async {
    try {
      await Haptics.vibrate(HapticsType.warning);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Error haptic
  /// Use for: error occurred
  static Future<void> error() async {
    try {
      await Haptics.vibrate(HapticsType.error);
    } catch (_) {
      // Silently fail on unsupported devices
    }
  }

  /// Notification haptic (deprecated - use specific type)
  /// Kept for backward compatibility
  static Future<void> notification({required bool success}) async {
    if (success) {
      await HapticService.success();
    } else {
      await HapticService.error();
    }
  }
}
