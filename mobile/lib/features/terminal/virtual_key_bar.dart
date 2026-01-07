import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Virtual Key Bar for terminal input
///
/// Phase 04: Mobile App
/// Provides ESC, CTRL, TAB, Arrow keys that mobile keyboards lack
/// Includes keyboard toggle button
class VirtualKeyBar extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onToggleKeyboard;

  const VirtualKeyBar({
    super.key,
    required this.onKeyPressed,
    required this.onToggleKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        border: Border(
          top: BorderSide(
            color: CatppuccinMocha.surface1.withValues(alpha: 0.5),
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
            color: CatppuccinMocha.mauve,
            onPressed: onKeyPressed,
          ),
          _KeyButton(
            label: 'CTRL',
            keySequence: '',
            color: CatppuccinMocha.blue,
            isToggle: true,
            onPressed: onKeyPressed,
          ),
          _KeyButton(
            label: 'TAB',
            keySequence: '\t',
            color: CatppuccinMocha.teal,
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
            onPressed: onToggleKeyboard,
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
        color: Colors.transparent,
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
              color: CatppuccinMocha.mauve.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: CatppuccinMocha.mauve,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle button (keyboard)
class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: CatppuccinMocha.subtext0,
          ),
        ),
      ),
    );
  }
}
