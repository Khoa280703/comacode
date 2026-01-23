import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/session_status.dart';
import '../models/vibe_session.dart';

/// Single tab item for session navigation
///
/// Phase 02: Multi-Session Tab Architecture
/// Tap to switch, long press for menu
class TabItem extends StatelessWidget {
  final VibeSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const TabItem({
    super.key,
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? CatppuccinMocha.surface0
              : CatppuccinMocha.mantle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _getBorderColor(),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator
            _StatusIndicator(status: session.status),
            const SizedBox(width: 6),
            // Session name
            Text(
              session.projectName,
              style: TextStyle(
                color: CatppuccinMocha.text,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more,
                size: 14,
                color: CatppuccinMocha.subtext0,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getBorderColor() {
    switch (session.status) {
      case SessionStatus.active:
        return CatppuccinMocha.mauve;
      case SessionStatus.idle:
        return CatppuccinMocha.surface1;
      case SessionStatus.busy:
        return CatppuccinMocha.yellow;
      case SessionStatus.error:
        return CatppuccinMocha.red;
    }
  }
}

class _StatusIndicator extends StatelessWidget {
  final SessionStatus status;

  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    double size;

    switch (status) {
      case SessionStatus.active:
        color = CatppuccinMocha.mauve;
        size = 6;
        break;
      case SessionStatus.idle:
        color = CatppuccinMocha.overlay1;
        size = 6;
        break;
      case SessionStatus.busy:
        // Spinner for busy status
        return SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(CatppuccinMocha.yellow),
          ),
        );
      case SessionStatus.error:
        color = CatppuccinMocha.red;
        size = 6;
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
