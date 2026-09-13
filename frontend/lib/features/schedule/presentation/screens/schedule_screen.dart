import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
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
    final slots = ScheduleMock.byDay[_selectedDay] ?? const [];
    final relation = _relationFor(_selectedDay);

    return AppScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Horario'),
      ),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
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
                    decoration: BoxDecoration(
                      color: selected ? palette.accentDeep : palette.cardElevated,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(
                        color: selected
                            ? palette.accentDeep
                            : Theme.of(context).dividerColor,
                      ),
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
                icon: Icons.event_available_outlined,
                title: 'Día libre',
                subtitle: 'No hay clases programadas para este día.',
              ),
            )
          else
            for (final slot in slots)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 16),
                child: _SlotCard(slot: slot, relation: relation),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Relación del día seleccionado con "hoy" (pasado / hoy / futuro), para
  /// derivar el estado y el progreso de cada clase.
  _DayRelation _relationFor(int dayIndex) {
    final weekday = DateTime.now().weekday; // 1=Lun .. 7=Dom
    if (weekday > 5) return _DayRelation.future; // fin de semana: semana próxima
    final todayIdx = weekday - 1;
    if (dayIndex < todayIdx) return _DayRelation.past;
    if (dayIndex > todayIdx) return _DayRelation.future;
    return _DayRelation.today;
  }
}

enum _DayRelation { past, today, future }

/// Estado + progreso de una clase, derivados de la hora real.
typedef _SlotStatus = ({String label, double progress});

/// Tarjeta de clase estilo "timeline" con tarjeta pastel por materia.
class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.relation});

  final ClassSlot slot;
  final _DayRelation relation;

  // Tinta oscura legible sobre cualquier pastel.
  static const _ink = Color(0xFF16202E);
  static const _diamondBg = Color(0xFF18212F);

  _SlotStatus _status() {
    switch (relation) {
      case _DayRelation.past:
        return (label: 'Finalizada', progress: 1);
      case _DayRelation.future:
        return (label: 'Próxima', progress: 0);
      case _DayRelation.today:
        final now = DateTime.now();
        final nowM = now.hour * 60 + now.minute;
        final s = DateUtilsX.hhmmToMinutes(slot.start);
        final e = DateUtilsX.hhmmToMinutes(slot.end);
        if (nowM < s) return (label: 'Próxima', progress: 0);
        if (nowM >= e) return (label: 'Finalizada', progress: 1);
        final p = (nowM - s) / math.max(1, e - s);
        return (label: 'En curso', progress: p.clamp(0.0, 1.0));
    }
  }

  String _initials() {
    final cleaned = slot.teacher.replaceAll(
      RegExp(r'^(Prof\.|Profa\.|Lic\.|Dra\.|Dr\.|Mtro\.|Mtra\.|Ing\.)\s*'),
      '',
    );
    final parts =
        cleaned.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = _status();

    final cardFill = Color.lerp(slot.color, Colors.white, 0.72)!;
    final glyph = Color.lerp(slot.color, Colors.white, 0.28)!;
    final inkMuted = _ink.withValues(alpha: 0.62);

    // Métricas de la pestaña "folder". El ancho se ajusta al texto del estado.
    const tabHeight = 36.0;
    const tabShoulder = 24.0;
    final labelStyle = context.textTheme.labelSmall?.copyWith(
      color: _ink,
      fontWeight: FontWeight.w800,
    );
    final labelPainter = TextPainter(
      text: TextSpan(text: status.label, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final tabWidth = labelPainter.width + 32; // 16 px de padding a cada lado

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline (hora inicio / punto / línea punteada / hora fin)
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  slot.start,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: slot.color),
                ),
                Expanded(
                  child: _DashedLine(color: palette.textMuted.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 4),
                Text(
                  slot.end,
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Tarjeta con pestaña "folder" integrada (misma silueta).
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Silueta tarjeta + pestaña, con sombra coherente.
                PhysicalShape(
                  clipper: _FolderCardClipper(
                    tabWidth: tabWidth,
                    tabHeight: tabHeight,
                    shoulder: tabShoulder,
                    radius: 22,
                    tabTopRadius: 12,
                  ),
                  color: cardFill,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  child: Padding(
                    padding: const EdgeInsets.only(top: tabHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
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
                                  ),
                                  child: Transform.rotate(
                                    angle: -math.pi / 4,
                                    child: Icon(
                                      slot.icon,
                                      color: glyph,
                                      size: 20,
                                    ),
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
                                  style:
                                      context.textTheme.titleMedium?.copyWith(
                                    color: _ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${slot.teacher} · ${slot.room}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _showDetails(context),
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.more_vert,
                                color: inkMuted,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Texto de estado dentro de la pestaña.
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: tabWidth,
                    height: tabHeight,
                    child: Center(
                      child: Text(status.label, style: labelStyle),
                    ),
                  ),
                ),
                // Avatar del maestro, flotando a la derecha de la pestaña.
                Positioned(
                  left: tabWidth + tabShoulder + 4,
                  top: -4,
                  child: _TeacherAvatar(
                    initials: _initials(),
                    color: slot.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.cardElevated,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: slot.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(slot.icon, color: slot.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      slot.subject,
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(icon: Icons.schedule, text: '${slot.start} – ${slot.end}'),
              _DetailRow(icon: Icons.person_outline, text: slot.teacher),
              _DetailRow(icon: Icons.place_outlined, text: slot.room),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar circular del maestro con iniciales.
class _TeacherAvatar extends StatelessWidget {
  const _TeacherAvatar({
    required this.initials,
    required this.color,
  });

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        initials,
        style: context.textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// Silueta de la tarjeta con pestaña "folder" arriba a la izquierda: el borde
/// izquierdo sube recto (continuo con la tarjeta) y el lado derecho de la
/// pestaña baja en curva hasta el borde superior del cuerpo.
class _FolderCardClipper extends CustomClipper<Path> {
  _FolderCardClipper({
    required this.tabWidth,
    required this.tabHeight,
    required this.shoulder,
    required this.radius,
    required this.tabTopRadius,
  });

  final double tabWidth;
  final double tabHeight;
  final double shoulder;
  final double radius;
  final double tabTopRadius;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final th = tabHeight;
    final tw = tabWidth;
    final r = radius;
    final tr = tabTopRadius;
    final sh = shoulder;

    return Path()
      // Borde superior de la pestaña (tras la esquina superior izquierda).
      ..moveTo(tr, 0)
      ..lineTo(tw, 0)
      // Hombro derecho en curva "ogee": tangente horizontal arriba (sigue el
      // borde de la pestaña) y abajo (se funde con el borde del cuerpo), sin
      // codo en la unión. Handles largos (0.8) => curva más pronunciada.
      ..cubicTo(tw + sh * 0.8, 0, tw + sh * 0.2, th, tw + sh, th)
      // Borde superior del cuerpo hasta la esquina superior derecha.
      ..lineTo(w - r, th)
      ..quadraticBezierTo(w, th, w, th + r)
      // Lado derecho y esquinas inferiores.
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      // Borde izquierdo recto hasta la esquina superior izquierda de la pestaña.
      ..lineTo(0, tr)
      ..quadraticBezierTo(0, 0, tr, 0)
      ..close();
  }

  @override
  bool shouldReclip(_FolderCardClipper oldClipper) =>
      oldClipper.tabWidth != tabWidth ||
      oldClipper.tabHeight != tabHeight ||
      oldClipper.shoulder != shoulder ||
      oldClipper.radius != radius ||
      oldClipper.tabTopRadius != tabTopRadius;
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

/// Fila de detalle dentro del bottom sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
