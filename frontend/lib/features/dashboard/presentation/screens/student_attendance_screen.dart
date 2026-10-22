import '../../../../core/network/provider_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/charts.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/utils/plural.dart';
import '../../../auth/presentation/identity_providers.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/attendance_month.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Asistencia del alumno: porcentaje total + calendario del mes con checks en
/// los días asistidos.
class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({
    super.key,
    this.title = 'Asistencia',
    this.heading = 'Tu asistencia',
    this.percentOverride,
    this.studentId,
  });

  /// Título de la barra superior y encabezado de la tarjeta (el panel del
  /// padre los adapta al hijo seleccionado).
  final String title;
  final String heading;

  /// Si se indica, reemplaza el porcentaje del alumno logueado.
  final double? percentOverride;

  /// Alumno cuya asistencia se muestra (el hijo en el panel del padre); si falta,
  /// se usa el del propio alumno.
  final int? studentId;

  // Días del mes con ausencia (mock demo).
  static const _absentDays = {9};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(studentDashboardProvider).scopedValue ??
        StudentDashboardData.empty();
    final pct = percentOverride?.round() ?? (data.attendanceRate * 100).round();
    final role = ref.watch(authControllerProvider).user?.activeRole;
    final id = studentId ??
        (role == AppRole.student
            ? ref.watch(currentStudentIdProvider).valueOrNull
            : null);
    // Sin backend (demo) o sin alumno conocido: calendario de ejemplo de siempre.
    final month = ref.watch(monthAttendanceProvider(id));

    return StudentDetailScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AttendanceHeader(
            percent: pct,
            heading: heading,
            real: month.valueOrNull,
            demo: id == null,
          ),
          const SizedBox(height: 20),
          if (month.hasError)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No se pudo cargar la asistencia de este mes.'),
            ),
          _MonthCalendar(
            absentDays: _absentDays,
            real: month.valueOrNull,
            demo: id == null,
          ),
          const SizedBox(height: 16),
          const _Legend(),
        ],
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader({
    required this.percent,
    required this.heading,
    required this.real,
    required this.demo,
  });
  final int percent;
  final String heading;
  final MonthAttendance? real;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DepthCard(
      brutal: true,
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
                  heading,
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  demo
                      ? 'Vas muy bien este mes 🎯'
                      : real == null || real!.isEmpty
                          ? 'Aún no hay asistencia registrada este mes'
                          : real!.absentDays == 0
                              ? 'Sin faltas este mes 🎯'
                              : 'Faltas este mes: ${real!.absentDays}',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 12),
                if (demo || (real?.streak ?? 0) > 0)
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
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: palette.success,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          demo
                              ? 'Racha de 12 días'
                              : 'Racha de ${plural(real!.streak, 'día')}',
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
  const _MonthCalendar({
    required this.absentDays,
    required this.real,
    required this.demo,
  });
  final Set<int> absentDays;
  final MonthAttendance? real;
  final bool demo;

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

    return BrutalBox(
      padding: const EdgeInsets.all(14),
      radius: Radii.lg,
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
    if (demo) {
      return absentDays.contains(day) ? _DayState.absent : _DayState.present;
    }
    // Datos reales: solo los días con registro se marcan; sin registro queda plano.
    final absent = real?.absentByDay[day];
    if (absent == null) return _DayState.future;
    return absent ? _DayState.absent : _DayState.present;
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
        // Los días con asistencia o falta llevan borde, como el resto de
        // tarjetas; fines de semana y días futuros quedan planos.
        border: bg == null
            ? null
            : Border.all(color: Brutal.ink(context), width: 1.5),
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
