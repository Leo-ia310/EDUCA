import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/brutal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/schedule_mock.dart';

/// Horario semanal. Alimenta la pestaña "Horario" del bottom nav y los
/// accesos "Ver Horario" / "Modificar Horarios".
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late int _selectedDay = ScheduleMock.todayIndex();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final slots = ScheduleMock.byDay[_selectedDay] ?? const <ClassSlot>[];

    return StudentDetailScaffold(
      title: 'Horario',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selector de día
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: ScheduleMock.days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = i == _selectedDay;
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
                          ScheduleMock.days[i],
                          style: context.textTheme.labelMedium?.copyWith(
                            color: selected
                                ? Colors.white
                                : palette.textMuted,
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
                                    ? Colors.white
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
          const SizedBox(height: 20),
          SectionHeader(title: ScheduleMock.daysLong[_selectedDay]),
          const SizedBox(height: 8),
          if (slots.isEmpty)
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
  const _Timeline({required this.start, required this.end, required this.color});

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
