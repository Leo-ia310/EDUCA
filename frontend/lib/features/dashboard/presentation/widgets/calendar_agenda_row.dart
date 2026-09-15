import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/school_calendar_data.dart';

/// Fila de agenda del calendario escolar: ícono por tipo (evento/tarea),
/// título y fecha + subtítulo. Se usa en el calendario y en el resumen del home.
class CalendarAgendaRow extends StatelessWidget {
  const CalendarAgendaRow({super.key, required this.item, this.onTap});

  final CalItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isTask = item.kind == CalKind.task;
    final color = isTask ? const Color(0xFFF3993E) : context.palette.accent;
    final s = context.pastel(color);
    final dateLabel = toBeginningOfSentenceCase(
      DateFormat("EEE d 'de' MMM", 'es').format(item.date),
    );
    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      onTap: onTap,
      borderRadius: Radii.md,
      padding: const EdgeInsets.all(12),
      child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                child: Icon(
                  isTask ? Icons.assignment_rounded : Icons.event_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(color: s.ink, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateLabel · ${item.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}
