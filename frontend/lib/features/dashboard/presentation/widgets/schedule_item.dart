import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/dashboard_models.dart';

class ScheduleItemRow extends StatelessWidget {
  const ScheduleItemRow({super.key, required this.slot});
  final ScheduleSlot slot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = slot.accent ?? subjectColor(slot.subject);
    final ink = slot.accent ?? subjectInk(slot.subject);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              slot.startTime,
              style: context.textTheme.titleSmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Marcador tipo línea de tiempo, en el color de la materia.
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              slot.icon ?? Icons.menu_book_rounded,
              size: 18,
              color: ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.subject,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  slot.room,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
