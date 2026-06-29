import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'edu_card.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.sublabel,
    this.icon,
    this.accent,
  });

  final String value;
  final String label;
  final String? sublabel;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return EduCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Icon(icon, size: 18, color: accent ?? context.palette.limeDeep),
            ),
          Text(
            value,
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.textTheme.bodySmall,
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel!,
              style: context.textTheme.labelSmall?.copyWith(
                color: accent ?? context.palette.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
