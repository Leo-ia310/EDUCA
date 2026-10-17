import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/brutal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../admin/data/admin_schedule.dart';
import '../../data/schedule_mock.dart';
import '../../providers.dart';

/// Horario semanal. Alimenta la pestaña "Horario" del bottom nav y los
/// accesos "Ver Horario" / "Modificar Horarios".
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({
    super.key,
    this.forChild = false,
    this.studentId,
    this.title = 'Horario',
    this.header,
  });

  /// Vista del padre: horario del hijo [studentId] (en vez del propio).
  final bool forChild;
  final int? studentId;
  final String title;

  /// Contenido opcional sobre el selector de día (p. ej. elegir hijo).
  final Widget? header;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late int _selectedDay = ScheduleMock.todayIndex();
  String? _shift;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final weekly = widget.forChild
        ? ref.watch(childWeeklySlotsProvider(widget.studentId))
        : ref.watch(weeklySlotsProvider);
    final byDay = weekly.valueOrNull ?? const <int, List<ClassSlot>>{};
    // Lun–Vie siempre; sábado/domingo solo si el admin los programó.
    final dayCount = byDay.entries
            .where((e) => e.value.isNotEmpty)
            .fold<int>(4, (m, e) => e.key > m ? e.key : m) +
        1;
    final selectedDay = _selectedDay < dayCount ? _selectedDay : 0;
    // Turnos presentes en el horario: si hay más de uno se puede filtrar.
    final shifts = {
      for (final day in byDay.values)
        for (final s in day)
          if (s.shift != null) s.shift!,
    };
    final activeShift = shifts.contains(_shift) ? _shift : null;
    final slots = [
      for (final s in byDay[selectedDay] ?? const <ClassSlot>[])
        if (activeShift == null || s.shift == null || s.shift == activeShift) s,
    ];

    return StudentDetailScaffold(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 12),
          ],
          // Selector de día
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: dayCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = i == selectedDay;
                final isToday = i == ScheduleMock.todayIndex();
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = i),
                  child: Container(
                    width: 58,
                    margin: const EdgeInsets.only(right: 3, bottom: 3),
                    decoration: Brutal.decoration(
                      context,
                      color:
                          selected ? palette.accentDeep : palette.cardElevated,
                      radius: Radii.md,
                      offset: 3,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ScheduleMock.weekDays[i],
                          style: context.textTheme.labelMedium?.copyWith(
                            color:
                                selected ? palette.onAccent : palette.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday
                                ? (selected
                                    ? palette.onAccent
                                    : palette.accentDeep)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (shifts.length > 1) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                BrutalPill(
                  compact: true,
                  label: 'Todos los turnos',
                  selected: activeShift == null,
                  onTap: () => setState(() => _shift = null),
                ),
                for (final code in scheduleShifts.map((s) => s.$1))
                  if (shifts.contains(code))
                    BrutalPill(
                      compact: true,
                      label: shiftLabel(code),
                      selected: activeShift == code,
                      onTap: () => setState(() => _shift = code),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SectionHeader(title: ScheduleMock.weekDaysLong[selectedDay]),
          const SizedBox(height: 8),
          if (weekly.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: SkeletonList(),
            )
          else if (weekly.hasError)
            ErrorStateView(
              message: 'No se pudo cargar el horario. Intenta nuevamente.',
              onRetry: () {
                if (widget.forChild) {
                  ref.invalidate(childWeeklySlotsProvider(widget.studentId));
                } else {
                  ref.invalidate(weeklySlotsProvider);
                }
              },
            )
          else if (byDay.values.every((day) => day.isEmpty))
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No tienes horario asignado',
                subtitle: 'Tu colegio aún no ha asignado clases a tu horario.',
              ),
            )
          else if (slots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.event_available_rounded,
                title: 'Día libre',
                subtitle: 'No hay clases programadas para este día.',
              ),
            )
          else
            for (final slot in slots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: slot.isBreak
                    ? _BreakRow(slot: slot)
                    : _SlotCard(slot: slot),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Columna de timeline: hora de inicio, punto, línea punteada y hora de fin.
class _Timeline extends StatelessWidget {
  const _Timeline(
      {required this.start, required this.end, required this.color,});

  final String start;
  final String end;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          Text(
            start,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Expanded(
            child: _DashedLine(color: palette.textMuted.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 4),
          Text(
            end,
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de clase: ícono, materia y maestro sobre fondo pastel.
class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});

  final ClassSlot slot;

  // Tinta oscura legible sobre cualquier pastel.
  static const _ink = Color(0xFF16202E);
  static const _diamondBg = Color(0xFF18212F);

  @override
  Widget build(BuildContext context) {
    final cardFill = Color.lerp(slot.color, Colors.white, 0.72)!;
    final glyph = Color.lerp(slot.color, Colors.white, 0.28)!;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Timeline(start: slot.start, end: slot.end, color: slot.color),
          const SizedBox(width: 10),
          Expanded(
            child: BrutalBox(
              color: cardFill,
              radius: Radii.lg,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: Center(
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _diamondBg,
                            borderRadius: BorderRadius.circular(Radii.sm),
                            border: Border.all(
                              color: Brutal.ink(context),
                              width: Brutal.border,
                            ),
                          ),
                          child: Transform.rotate(
                            angle: -math.pi / 4,
                            child: Icon(slot.icon, color: glyph, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slot.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleMedium?.copyWith(
                            color: _ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          slot.teacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: _ink.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Receso: sin tarjeta, solo el espacio con su hora, nombre e ilustración.
class _BreakRow extends StatelessWidget {
  const _BreakRow({required this.slot});

  final ClassSlot slot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Timeline(start: slot.start, end: slot.end, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Image.asset(
                  'assets/images/break_relax.png',
                  height: 110,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.subject,
                        style: context.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${slot.start} – ${slot.end}',
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: palette.textMuted),
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

/// Línea vertical punteada para el timeline.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      child: CustomPaint(
        painter: _DashedLinePainter(color),
        size: const Size(2, double.infinity),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 5.0;
    double y = 0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
