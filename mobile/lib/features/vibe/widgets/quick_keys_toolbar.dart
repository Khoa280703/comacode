import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/special_key.dart';
import '../services/haptic_service.dart';

/// Quick keys toolbar for common terminal interactions
class QuickKeysToolbar extends StatelessWidget {
  final Function(SpecialKey) onKeyPressed;

  const QuickKeysToolbar({
    super.key,
    required this.onKeyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        border: Border(
          top: BorderSide(color: CatppuccinMocha.surface1, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickKeyButton(
              label: SpecialKey.arrowUp.label,
              specialKey: SpecialKey.arrowUp,
              onTap: () => onKeyPressed(SpecialKey.arrowUp),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.arrowDown.label,
              specialKey: SpecialKey.arrowDown,
              onTap: () => onKeyPressed(SpecialKey.arrowDown),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.tab.label,
              specialKey: SpecialKey.tab,
              onTap: () => onKeyPressed(SpecialKey.tab),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.ctrlD.label,
              specialKey: SpecialKey.ctrlD,
              onTap: () => onKeyPressed(SpecialKey.ctrlD),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.ctrlL.label,
              specialKey: SpecialKey.ctrlL,
              onTap: () => onKeyPressed(SpecialKey.ctrlL),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.enter.label,
              specialKey: SpecialKey.enter,
              onTap: () => onKeyPressed(SpecialKey.enter),
              isDestructive: false,
            ),
            _QuickKeyButton(
              label: SpecialKey.ctrlC.label,
              specialKey: SpecialKey.ctrlC,
              onTap: () => onKeyPressed(SpecialKey.ctrlC),
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickKeyButton extends StatefulWidget {
  final String label;
  final SpecialKey specialKey;
  final VoidCallback onTap;
  final bool isDestructive;

  const _QuickKeyButton({
    required this.label,
    required this.specialKey,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_QuickKeyButton> createState() => _QuickKeyButtonState();
}

class _QuickKeyButtonState extends State<_QuickKeyButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticService.selection();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _isPressed
              ? CatppuccinMocha.surface1
              : CatppuccinMocha.surface0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isDestructive
                ? CatppuccinMocha.red.withValues(alpha: 0.5)
                : CatppuccinMocha.surface1,
            width: 1,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.isDestructive
                ? CatppuccinMocha.red
                : CatppuccinMocha.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
