import 'package:flutter/material.dart';

/// Virtual Key Bar for terminal input
///
/// Phase 04: Mobile App
/// Provides ESC, CTRL, TAB, Arrow keys that mobile keyboards lack
/// Includes keyboard/wakelock toggle buttons
class VirtualKeyBar extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onToggleKeyboard;
  final VoidCallback onToggleWakelock;
  final bool isKeyboardVisible;
  final bool isWakelockEnabled;

  const VirtualKeyBar({
    super.key,
    required this.onKeyPressed,
    required this.onToggleKeyboard,
    required this.onToggleWakelock,
    this.isKeyboardVisible = true,
    this.isWakelockEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Special keys
          _KeyButton(
            label: 'ESC',
            keySequence: '\x1b',
            color: const Color(0xFFCBA6F7), // Mauve
            onPressed: onKeyPressed,
          ),
          _KeyButton(
            label: 'CTRL',
            keySequence: '',
            color: const Color(0xFF89B4FA), // Blue
            isToggle: true,
            onPressed: onKeyPressed,
          ),
          _KeyButton(
            label: 'TAB',
            keySequence: '\t',
            color: const Color(0xFF94E2D5), // Teal
            onPressed: onKeyPressed,
          ),
          const SizedBox(width: 8),
          _ArrowButton(label: '↑', keySequence: '\x1b[A', onPressed: onKeyPressed),
          _ArrowButton(label: '↓', keySequence: '\x1b[B', onPressed: onKeyPressed),
          _ArrowButton(label: '←', keySequence: '\x1b[D', onPressed: onKeyPressed),
          _ArrowButton(label: '→', keySequence: '\x1b[C', onPressed: onKeyPressed),

          const Spacer(),

          // Toggle controls (right side)
          _ToggleButton(
            icon: Icons.keyboard,
            tooltip: 'Toggle keyboard',
            isActive: isKeyboardVisible,
            onPressed: onToggleKeyboard,
          ),
          const SizedBox(width: 8),
          _ToggleButton(
            icon: isWakelockEnabled ? Icons.lock : Icons.lock_outline,
            tooltip: isWakelockEnabled ? 'Wakelock on' : 'Wakelock off',
            isActive: isWakelockEnabled,
            onPressed: onToggleWakelock,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Special key button (ESC, CTRL, TAB)
class _KeyButton extends StatelessWidget {
  final String label;
  final String keySequence;
  final Color color;
  final bool isToggle;
  final Function(String) onPressed;

  const _KeyButton({
    required this.label,
    required this.keySequence,
    required this.color,
    required this.onPressed,
    this.isToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: isToggle && _ctrlPressed
            ? color.withValues(alpha: 0.3)
            : Colors.transparent,
        child: InkWell(
          onTap: () => onPressed(keySequence),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Arrow key button
class _ArrowButton extends StatelessWidget {
  final String label;
  final String keySequence;
  final Function(String) onPressed;

  const _ArrowButton({
    required this.label,
    required this.keySequence,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      child: InkWell(
        onTap: () => onPressed(keySequence),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle button (keyboard/wakelock)
class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// Global state for CTRL key tracking (simple implementation)
bool _ctrlPressed = false;
