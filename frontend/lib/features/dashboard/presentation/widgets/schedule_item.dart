import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/dashboard_models.dart';

class ScheduleItemRow extends StatelessWidget {
  const ScheduleItemRow({
    super.key,
    required this.slot,
    this.highlighted = false,
    this.badge,
  });

  final ScheduleSlot slot;

  /// Resalta la fila (clase en curso) con un fondo tenue en el color de la
  /// materia.
  final bool highlighted;

  /// Etiqueta corta a la derecha del nombre ("Ahora", "En 20 min").
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = slot.accent ?? subjectColor(slot.subject);
    final ink = slot.accent ?? subjectInk(slot.subject);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 46,
          child: Text(
            slot.startTime,
            style: context.textTheme.titleSmall?.copyWith(
              color: highlighted ? ink : palette.textMuted,
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      slot.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    _Badge(label: badge!, accent: accent, ink: ink,
                        filled: highlighted),
                  ],
                ],
              ),
              Text(
                slot.room,
                style: context.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );

    if (!highlighted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: row,
      );
    }
    // Clase en curso: fondo tenue en el color de la materia.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: row,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.accent,
    required this.ink,
    required this.filled,
  });

  final String label;
  final Color accent;
  final Color ink;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? ink : accent.withValues(alpha: 0.16),
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
