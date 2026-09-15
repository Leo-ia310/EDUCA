import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/charts.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Asistencia del alumno: porcentaje total + calendario del mes con checks en
/// los días asistidos.
class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({super.key});

  // Días del mes con ausencia (mock demo).
  static const _absentDays = {9};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();
    final pct = (data.attendanceRate * 100).round();

    return StudentDetailScaffold(
      title: 'Asistencia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AttendanceHeader(percent: pct),
          const SizedBox(height: 20),
          const _MonthCalendar(absentDays: _absentDays),
          const SizedBox(height: 16),
          const _Legend(),
        ],
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DepthCard(
      borderRadius: Radii.xl,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AttendanceRing(percent: percent, size: 128),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu asistencia',
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vas muy bien este mes 🎯',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          color: palette.success, size: 18,),
                      const SizedBox(width: 6),
                      Text(
                        'Racha de 12 días',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: palette.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.absentDays});
  final Set<int> absentDays;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leading = firstDay.weekday - 1; // lunes primero
    final monthLabel = toBeginningOfSentenceCase(
      DateFormat("MMMM 'de' y", 'es').format(now),
    );

    const labels = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];

    // Celdas: espacios en blanco iniciales + los días del mes.
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: day,
          state: _stateFor(day, now, today),
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
        ],
      ),
    );
  }

  _DayState _stateFor(int day, DateTime now, DateTime today) {
    final d = DateTime(now.year, now.month, day);
    if (d.weekday >= 6) return _DayState.weekend;
    if (d.isAfter(today)) return _DayState.future;
    if (absentDays.contains(day)) return _DayState.absent;
    return _DayState.present;
  }
}

enum _DayState { present, absent, weekend, future }

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.state});
  final int day;
  final _DayState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    switch (state) {
      case _DayState.present:
        return _cell(
          context,
          bg: palette.success.withValues(alpha: 0.18),
          child: Icon(Icons.check_rounded, color: palette.success, size: 18),
          day: day,
          dayColor: palette.success,
        );
      case _DayState.absent:
        return _cell(
          context,
          bg: palette.danger.withValues(alpha: 0.15),
          child: Icon(Icons.close_rounded, color: palette.danger, size: 18),
          day: day,
          dayColor: palette.danger,
        );
      case _DayState.weekend:
        return _cell(context, day: day, dayColor: palette.textMuted);
      case _DayState.future:
        return _cell(context, day: day, dayColor: palette.textMuted);
    }
  }

  Widget _cell(
    BuildContext context, {
    required int day,
    required Color dayColor,
    Color? bg,
    Widget? child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: context.textTheme.labelSmall?.copyWith(
              color: dayColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (child != null) ...[const SizedBox(height: 1), child],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        _dot(context, palette.success, 'Asistió'),
        const SizedBox(width: 16),
        _dot(context, palette.danger, 'Faltó'),
      ],
    );
  }

  Widget _dot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.textTheme.bodySmall),
      ],
    );
  }
}
