import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../schedule/data/schedule_mock.dart';

/// Sección "Horario" del home: carrusel de días (lun–vie, con la fecha y
/// "Hoy" en el actual) y las tarjetas de clases del día seleccionado.
class HomeScheduleSection extends StatefulWidget {
  const HomeScheduleSection({super.key});

  @override
  State<HomeScheduleSection> createState() => _HomeScheduleSectionState();
}

class _HomeScheduleSectionState extends State<HomeScheduleSection> {
  late final int _todayIdx = ScheduleMock.todayIndex();
  late int _selected = _todayIdx;

  /// Fecha del día `i` (0 = lunes) de la semana en curso.
  DateTime _dateFor(int i) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: i));
  }

  @override
  Widget build(BuildContext context) {
    final slots = ScheduleMock.byDay[_selected] ?? const <ClassSlot>[];
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final weekend = now.weekday > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Horario', accent: false),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _DayPill(
              label: ScheduleMock.days[i],
              date: _dateFor(i),
              isToday: i == _todayIdx && !weekend,
              selected: i == _selected,
              onTap: () => setState(() => _selected = i),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final (i, slot) in slots.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          if (slot.isBreak)
            _BreakCard(slot: slot)
          else
            _ClassCard(
              slot: slot,
              current: _selected == _todayIdx &&
                  !weekend &&
                  nowMin >= DateUtilsX.hhmmToMinutes(slot.start) &&
                  nowMin < DateUtilsX.hhmmToMinutes(slot.end),
            ),
        ],
      ],
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.label,
    required this.date,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? Colors.white : palette.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.accentDeep : palette.cardElevated,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color:
                selected ? palette.accentDeep : Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
            Text(
              '${date.day}',
              style: context.textTheme.titleMedium?.copyWith(
                color: selected ? Colors.white : null,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            SizedBox(
              height: 14,
              child: isToday
                  ? Text(
                      'Hoy',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: selected ? Colors.white : palette.accentDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.slot, required this.current});
  final ClassSlot slot;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(slot.color);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(Routes.schedule),
        borderRadius: BorderRadius.circular(Radii.xl),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: current ? Border.all(color: s.vivid, width: 1.8) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleLarge?.copyWith(
                        color: s.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 14, color: s.inkMuted,),
                        const SizedBox(width: 5),
                        Text(
                          slot.start,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: s.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6,),
                      decoration: BoxDecoration(
                        color: s.vivid.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_circle_rounded,
                              size: 20, color: s.vivid,),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              slot.teacher,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.labelMedium?.copyWith(
                                color: s.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 38,
                height: 38,
                decoration:
                    BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 24,),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakCard extends StatelessWidget {
  const _BreakCard({required this.slot});
  final ClassSlot slot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: palette.cardElevated,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(slot.icon, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              slot.subject,
              style: context.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${slot.start} – ${slot.end}',
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
