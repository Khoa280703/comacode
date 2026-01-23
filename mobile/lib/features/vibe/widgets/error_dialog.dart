import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../services/haptic_service.dart';

/// Error type for categorization
enum ErrorType {
  /// Network/connection errors
  connection,

  /// Authentication/session errors
  authentication,

  /// File operation errors
  file,

  /// Dictation/speech errors
  dictation,

  /// Generic errors
  generic,
}

/// Error data for dialogs
class ErrorData {
  final String title;
  final String message;
  final ErrorType type;
  final List<ErrorAction>? actions;

  const ErrorData({
    required this.title,
    required this.message,
    required this.type,
    this.actions,
  });

  /// Create connection lost error
  factory ErrorData.connectionLost({
    String? message,
    VoidCallback? onReconnect,
    VoidCallback? onNewSession,
  }) {
    return ErrorData(
      title: 'Connection Lost',
      message: message ?? 'Claude stopped responding. The connection may have been interrupted.',
      type: ErrorType.connection,
      actions: [
        if (onReconnect != null)
          ErrorAction(
            label: 'Reconnect',
            type: ErrorActionType.primary,
            onPressed: onReconnect,
          ),
        if (onNewSession != null)
          ErrorAction(
            label: 'Start New Session',
            type: ErrorActionType.secondary,
            onPressed: onNewSession,
          ),
      ],
    );
  }

  /// Create dictation error
  factory ErrorData.dictationFailed({
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorData(
      title: 'Dictation Failed',
      message: message ?? 'Could not capture speech. Please check microphone permissions.',
      type: ErrorType.dictation,
      actions: [
        if (onRetry != null)
          ErrorAction(
            label: 'Retry',
            type: ErrorActionType.primary,
            onPressed: onRetry,
          ),
        ErrorAction(
          label: 'Cancel',
          type: ErrorActionType.secondary,
          onPressed: () {},
        ),
      ],
    );
  }

  /// Create file read error
  factory ErrorData.fileReadFailed({
    required String filePath,
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onSkip,
  }) {
    return ErrorData(
      title: 'File Read Failed',
      message: message ?? 'Could not read file: $filePath',
      type: ErrorType.file,
      actions: [
        if (onRetry != null)
          ErrorAction(
            label: 'Retry',
            type: ErrorActionType.primary,
            onPressed: onRetry,
          ),
        if (onSkip != null)
          ErrorAction(
            label: 'Skip',
            type: ErrorActionType.secondary,
            onPressed: onSkip,
          ),
      ],
    );
  }

  /// Create generic error
  factory ErrorData.generic({
    required String title,
    required String message,
    VoidCallback? onDismiss,
  }) {
    return ErrorData(
      title: title,
      message: message,
      type: ErrorType.generic,
      actions: [
        if (onDismiss != null)
          ErrorAction(
            label: 'OK',
            type: ErrorActionType.primary,
            onPressed: onDismiss,
          ),
      ],
    );
  }
}

/// Error action type
enum ErrorActionType {
  primary,
  secondary,
  destructive,
}

/// Error action button
class ErrorAction {
  final String label;
  final ErrorActionType type;
  final VoidCallback onPressed;

  const ErrorAction({
    required this.label,
    required this.type,
    required this.onPressed,
  });
}

/// Error dialog for Vibe Coding
///
/// Shows categorized errors with appropriate actions and haptic feedback.
class VibeErrorDialog extends StatelessWidget {
  final ErrorData error;

  const VibeErrorDialog({
    super.key,
    required this.error,
  });

  /// Show error dialog
  static Future<void> show(
    BuildContext context,
    ErrorData error,
  ) async {
    // Haptic feedback for error
    await HapticService.heavy();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => VibeErrorDialog(error: error),
    );
  }

  /// Show connection lost dialog
  static Future<void> showConnectionLost({
    required BuildContext context,
    String? message,
    VoidCallback? onReconnect,
    VoidCallback? onNewSession,
  }) async {
    await show(
      context,
      ErrorData.connectionLost(
        message: message,
        onReconnect: onReconnect,
        onNewSession: onNewSession,
      ),
    );
  }

  /// Show dictation failed dialog
  static Future<void> showDictationFailed({
    required BuildContext context,
    String? message,
    VoidCallback? onRetry,
  }) async {
    await show(
      context,
      ErrorData.dictationFailed(
        message: message,
        onRetry: onRetry,
      ),
    );
  }

  /// Show file read failed dialog
  static Future<void> showFileReadFailed({
    required BuildContext context,
    required String filePath,
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onSkip,
  }) async {
    await show(
      context,
      ErrorData.fileReadFailed(
        filePath: filePath,
        message: message,
        onRetry: onRetry,
        onSkip: onSkip,
      ),
    );
  }

  /// Show generic error dialog
  static Future<void> showGeneric({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onDismiss,
  }) async {
    await show(
      context,
      ErrorData.generic(
        title: title,
        message: message,
        onDismiss: onDismiss,
      ),
    );
  }

  Color _getErrorColor() {
    return switch (error.type) {
      ErrorType.connection => CatppuccinMocha.red,
      ErrorType.authentication => CatppuccinMocha.yellow,
      ErrorType.file => CatppuccinMocha.red,
      ErrorType.dictation => CatppuccinMocha.yellow,
      ErrorType.generic => CatppuccinMocha.red,
    };
  }

  IconData _getErrorIcon() {
    return switch (error.type) {
      ErrorType.connection => Icons.wifi_off,
      ErrorType.authentication => Icons.lock_outline,
      ErrorType.file => Icons.insert_drive_file_outlined,
      ErrorType.dictation => Icons.mic_off,
      ErrorType.generic => Icons.error_outline,
    };
  }

  Color _getActionColor(ErrorActionType type) {
    return switch (type) {
      ErrorActionType.primary => CatppuccinMocha.mauve,
      ErrorActionType.secondary => CatppuccinMocha.surface1,
      ErrorActionType.destructive => CatppuccinMocha.red,
    };
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = _getErrorColor();

    return AlertDialog(
      backgroundColor: CatppuccinMocha.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: errorColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      title: Row(
        children: [
          Icon(
            _getErrorIcon(),
            color: errorColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error.title,
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        error.message,
        style: TextStyle(
          color: CatppuccinMocha.subtext0,
          fontSize: 14,
        ),
      ),
      actions: error.actions?.map((action) {
        return TextButton(
          onPressed: () {
            HapticService.selection();
            action.onPressed();
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: _getActionColor(action.type),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          child: Text(
            action.label,
            style: TextStyle(
              fontWeight: action.type == ErrorActionType.primary
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Error banner for inline error display
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;
  final ErrorType type;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onRetry,
    this.type = ErrorType.generic,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      ErrorType.connection => CatppuccinMocha.red,
      ErrorType.authentication => CatppuccinMocha.yellow,
      ErrorType.file => CatppuccinMocha.red,
      ErrorType.dictation => CatppuccinMocha.yellow,
      ErrorType.generic => CatppuccinMocha.red,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: CatppuccinMocha.text, fontSize: 14),
            ),
          ),
          if (onRetry != null) ...[
            TextButton(
              onPressed: () {
                HapticService.selection();
                onRetry!();
              },
              child: Text(
                'Retry',
                style: TextStyle(color: CatppuccinMocha.mauve),
              ),
            ),
          ],
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close, color: CatppuccinMocha.text, size: 18),
              onPressed: () {
                HapticService.selection();
                onDismiss!();
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
        ],
      ),
    );
  }
}
