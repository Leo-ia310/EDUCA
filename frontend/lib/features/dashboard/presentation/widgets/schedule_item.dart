import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/dashboard_models.dart';

/// Fila del "Horario de hoy" como tarjeta pastel por materia: hora, ícono en
/// círculo vívido, nombre y aula, con un badge opcional ("Ahora", "En 20 min").
/// La clase en curso se resalta con un borde en el color de la materia.
class ScheduleItemRow extends StatelessWidget {
  const ScheduleItemRow({
    super.key,
    required this.slot,
    this.highlighted = false,
    this.badge,
  });

  final ScheduleSlot slot;
  final bool highlighted;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(slot.accent ?? subjectColor(slot.subject));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? Border.all(color: s.vivid, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              slot.startTime,
              style: context.textTheme.titleSmall?.copyWith(
                color: s.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(
              slot.icon ?? Icons.menu_book_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        slot.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      _Badge(
                        label: badge!,
                        vivid: s.vivid,
                        ink: s.ink,
                        filled: highlighted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  slot.room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: s.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.vivid,
    required this.ink,
    required this.filled,
  });

  final String label;
  final Color vivid;
  final Color ink;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? vivid : vivid.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: filled ? Colors.white : ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
