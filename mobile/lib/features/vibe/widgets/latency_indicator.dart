import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Shows current connection latency for SSH Terminal Mode
///
/// Phase 2: Displays RTT (Round Trip Time) with color coding
/// and prediction status indicator.
class LatencyIndicator extends StatelessWidget {
  final Duration latency;
  final bool predictionEnabled;

  const LatencyIndicator({
    super.key,
    required this.latency,
    required this.predictionEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final ms = latency.inMilliseconds;
    final color = ms < 50
        ? CatppuccinMocha.green
        : ms < 150
            ? CatppuccinMocha.yellow
            : CatppuccinMocha.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface0,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${ms}ms',
            style: const TextStyle(
              color: CatppuccinMocha.subtext0,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          if (predictionEnabled) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.flash_on,
              size: 12,
              color: CatppuccinMocha.yellow,
            ),
          ],
        ],
      ),
    );
  }
}
