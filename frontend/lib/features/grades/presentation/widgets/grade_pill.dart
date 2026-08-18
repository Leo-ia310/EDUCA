import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

/// Píldora coloreada que muestra un score según la escala.
class GradePill extends StatelessWidget {
  const GradePill({
    super.key,
    required this.score,
    required this.scale,
    this.dense = false,
    this.showLabel = true,
  });

  final double score;
  final GradingScale scale;
  final bool dense;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final range = scale.ranges.firstWhere(
      (r) => r.contains(score),
      orElse: () => scale.ranges.last,
    );
    final color = range.color ?? palette.info;
    final display = _display();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            display,
            style: (dense
                    ? context.textTheme.labelSmall
                    : context.textTheme.labelMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
          if (showLabel && scale.type == ScaleType.qualitative) ...[
            const SizedBox(width: 6),
            Text(
              range.label,
              style: context.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _display() {
    if (scale.type == ScaleType.qualitative) {
      final range = scale.ranges.firstWhere(
        (r) => r.contains(score),
        orElse: () => scale.ranges.last,
      );
      return range.label;
    }
    return score.toStringAsFixed(scale.decimals);
  }
}
