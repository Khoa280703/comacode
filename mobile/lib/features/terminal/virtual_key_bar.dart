import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Virtual Key Bar for terminal input
///
/// Phase 04: Mobile App
/// Provides ESC, CTRL, TAB, Arrow keys that mobile keyboards lack
/// Phase 06 Fix: Added Ctrl combinations (Ctrl+C, Ctrl+D, Ctrl+Z)
class VirtualKeyBar extends StatefulWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onToggleKeyboard;

  const VirtualKeyBar({
    super.key,
    required this.onKeyPressed,
    required this.onToggleKeyboard,
  });

  @override
  State<VirtualKeyBar> createState() => _VirtualKeyBarState();
}

class _VirtualKeyBarState extends State<VirtualKeyBar> {
  bool _showCtrlKeys = false;

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
      child: _showCtrlKeys ? _buildCtrlKeys() : _buildNormalKeys(),
    );
  }

  Widget _buildNormalKeys() {
    return Row(
      children: [
        // Special keys
        _KeyButton(
          label: 'ESC',
          keySequence: '\x1b',
          color: CatppuccinMocha.mauve,
          onPressed: widget.onKeyPressed,
        ),
        _KeyButton(
          label: 'CTRL',
          keySequence: '',
          color: CatppuccinMocha.blue,
          onPressed: (_) => setState(() => _showCtrlKeys = true),
          highlighted: _showCtrlKeys,
        ),
        _KeyButton(
          label: 'TAB',
          keySequence: '\t',
          color: CatppuccinMocha.teal,
          onPressed: widget.onKeyPressed,
        ),
        const SizedBox(width: 4),
        _ArrowButton(label: '↑', keySequence: '\x1b[A', onPressed: widget.onKeyPressed),
        _ArrowButton(label: '↓', keySequence: '\x1b[B', onPressed: widget.onKeyPressed),
        _ArrowButton(label: '←', keySequence: '\x1b[D', onPressed: widget.onKeyPressed),
        _ArrowButton(label: '→', keySequence: '\x1b[C', onPressed: widget.onKeyPressed),

        const Spacer(),

        // Toggle controls (right side)
        _ToggleButton(
          icon: Icons.keyboard,
          tooltip: 'Toggle keyboard',
          onPressed: widget.onToggleKeyboard,
        ),
      ],
    );
  }

  Widget _buildCtrlKeys() {
    return Row(
      children: [
        // Ctrl combinations
        _KeyButton(
          label: 'Ctrl+C',
          keySequence: '\x03', // ETX - End of Text
          color: CatppuccinMocha.red,
          onPressed: (key) {
            widget.onKeyPressed(key);
            setState(() => _showCtrlKeys = false);
          },
        ),
        _KeyButton(
          label: 'Ctrl+D',
          keySequence: '\x04', // EOT - End of Transmission
          color: CatppuccinMocha.yellow,
          onPressed: (key) {
            widget.onKeyPressed(key);
            setState(() => _showCtrlKeys = false);
          },
        ),
        _KeyButton(
          label: 'Ctrl+Z',
          keySequence: '\x1a', // SUB - Suspend
          color: CatppuccinMocha.blue,
          onPressed: (key) {
            widget.onKeyPressed(key);
            setState(() => _showCtrlKeys = false);
          },
        ),
        _KeyButton(
          label: 'Ctrl+L',
          keySequence: '\x0c', // FF - Form Feed (clear screen)
          color: CatppuccinMocha.teal,
          onPressed: (key) {
            widget.onKeyPressed(key);
            setState(() => _showCtrlKeys = false);
          },
        ),

        const Spacer(),

        // Back button
        _KeyButton(
          label: '← Back',
          keySequence: '',
          color: CatppuccinMocha.mauve,
          onPressed: (_) => setState(() => _showCtrlKeys = false),
        ),
      ],
    );
  }
}

/// Special key button (ESC, CTRL, TAB, Ctrl+X)
class _KeyButton extends StatelessWidget {
  final String label;
  final String keySequence;
  final Color color;
  final Function(String) onPressed;
  final bool highlighted;

  const _KeyButton({
    required this.label,
    required this.keySequence,
    required this.color,
    required this.onPressed,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onPressed(keySequence),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: highlighted ? color.withValues(alpha: 0.2) : Colors.transparent,
              border: Border.all(
                color: color.withValues(alpha: highlighted ? 1.0 : 0.5),
                width: highlighted ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: highlighted ? FontWeight.bold : FontWeight.w500,
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
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 38,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: CatppuccinMocha.mauve.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: CatppuccinMocha.mauve,
                fontSize: 12,
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
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: CatppuccinMocha.subtext0,
          ),
        ),
      ),
    );
  }
}
