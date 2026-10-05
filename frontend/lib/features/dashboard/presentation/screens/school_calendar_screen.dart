import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/school_calendar_data.dart';
import '../widgets/calendar_agenda_row.dart';
import '../widgets/student_chrome.dart';

/// Calendario escolar del alumno (destino del botón "Calendario" del navbar):
/// calendario del mes con marcadores + lista de eventos escolares y tareas
/// próximas.
class SchoolCalendarScreen extends StatelessWidget {
  const SchoolCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = schoolCalendarItems(now);

    // Días del mes actual con eventos / tareas (para marcadores).
    final taskDays = <int>{};
    final eventDays = <int>{};
    for (final it in items) {
      if (it.date.year == now.year && it.date.month == now.month) {
        (it.kind == CalKind.task ? taskDays : eventDays).add(it.date.day);
      }
    }

    return StudentDetailScaffold(
      title: 'Calendario',
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthGrid(taskDays: taskDays, eventDays: eventDays),
          const SizedBox(height: 20),
          Text(
            'Próximos',
            style: context.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final it in items) ...[
            CalendarAgendaRow(item: it),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.taskDays, required this.eventDays});
  final Set<int> taskDays;
  final Set<int> eventDays;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leading = firstDay.weekday - 1;
    final monthLabel = toBeginningOfSentenceCase(
      DateFormat("MMMM 'de' y", 'es').format(now),
    );
    const labels = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayDot(
          day: day,
          isToday: day == now.day,
          hasTask: taskDays.contains(day),
          hasEvent: eventDays.contains(day),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.cardElevated,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: AppShadows.soft(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            monthLabel,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: cells,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _dot(context, palette.accent, 'Evento'),
              const SizedBox(width: 16),
              _dot(context, const Color(0xFFF3993E), 'Tarea'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.textTheme.bodySmall),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.day,
    required this.isToday,
    required this.hasTask,
    required this.hasEvent,
  });
  final int day;
  final bool isToday;
  final bool hasTask;
  final bool hasEvent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: isToday ? palette.accentSoft : null,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: context.textTheme.labelSmall?.copyWith(
              color: isToday ? palette.accentDeep : null,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasEvent) _tinyDot(palette.accent),
              if (hasEvent && hasTask) const SizedBox(width: 2),
              if (hasTask) _tinyDot(const Color(0xFFF3993E)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyDot(Color color) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
