import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/dashboard_models.dart';

class ScheduleItemRow extends StatelessWidget {
  const ScheduleItemRow({super.key, required this.slot});
  final ScheduleSlot slot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              slot.startTime,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              slot.icon ?? Icons.menu_book_rounded,
              size: 18,
              color: palette.limeDeep,
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
