import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../schedule/data/schedule_mock.dart';

/// Sección "Horario" del home: píldoras de días (lun–vie, con la fecha y
/// "Hoy" en el actual) y un carrusel de tarjetas verticales con las clases
/// del día seleccionado (siempre una centrada, asomando las vecinas).
class HomeScheduleSection extends StatefulWidget {
  const HomeScheduleSection({super.key});

  @override
  State<HomeScheduleSection> createState() => _HomeScheduleSectionState();
}

class _HomeScheduleSectionState extends State<HomeScheduleSection> {
  static const _cardHeight = 250.0;

  late final int _todayIdx = ScheduleMock.todayIndex();
  late int _selected = _todayIdx;
  late PageController _controller = _controllerFor(_selected);

  bool get _weekend => DateTime.now().weekday > 5;

  /// Fecha del día `i` (0 = lunes) de la semana en curso.
  DateTime _dateFor(int i) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: i));
  }

  /// Hoy arranca en la clase en curso (o la siguiente); otros días, en la 1.ª.
  PageController _controllerFor(int day) {
    var initial = 0;
    if (day == _todayIdx && !_weekend) {
      final now = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;
      final slots = ScheduleMock.byDay[day] ?? const <ClassSlot>[];
      final i = slots.indexWhere(
        (s) => !s.isBreak && nowMin < DateUtilsX.hhmmToMinutes(s.end),
      );
      if (i >= 0) initial = i;
    }
    return PageController(viewportFraction: 0.78, initialPage: initial);
  }

  void _select(int day) {
    if (day == _selected) return;
    final old = _controller;
    setState(() {
      _selected = day;
      _controller = _controllerFor(day);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = ScheduleMock.byDay[_selected] ?? const <ClassSlot>[];
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Horario', accent: false),
        const SizedBox(height: 6),
        // Altura fija: la píldora seleccionada sube sin mover el resto.
        SizedBox(
          height: 82,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _DayPill(
                    label: ScheduleMock.days[i],
                    date: _dateFor(i),
                    isToday: i == _todayIdx && !_weekend,
                    selected: i == _selected,
                    onTap: () => _select(i),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Se extiende al ancho completo para que se asomen las vecinas.
        SizedBox(
          height: _cardHeight,
          child: LayoutBuilder(
            builder: (context, c) => OverflowBox(
              maxWidth: c.maxWidth + 32,
              minWidth: c.maxWidth + 32,
              maxHeight: _cardHeight,
              child: SizedBox(
                height: _cardHeight,
                width: c.maxWidth + 32,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: PageView.builder(
                key: ValueKey(_selected),
                controller: _controller,
                clipBehavior: Clip.none,
                itemCount: slots.length,
                itemBuilder: (context, i) {
                  final slot = slots[i];
                  return _CarouselItem(
                    controller: _controller,
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: slot.isBreak
                          ? _BreakCard(slot: slot)
                          : _ClassCard(
                              slot: slot,
                              current: _selected == _todayIdx &&
                                  !_weekend &&
                                  nowMin >=
                                      DateUtilsX.hhmmToMinutes(slot.start) &&
                                  nowMin <
                                      DateUtilsX.hhmmToMinutes(slot.end),
                            ),
                    ),
                  );
                },
              ),
              ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Escala levemente las tarjetas que no están al centro.
class _CarouselItem extends StatelessWidget {
  const _CarouselItem({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final page = controller.hasClients &&
                controller.position.haveDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final delta = (page - index).abs().clamp(0.0, 1.0);
        return Transform.scale(scale: 1 - 0.08 * delta, child: child);
      },
      child: child,
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
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AnimatedContainer(
          duration: context.motion(AppMotion.base),
          curve: AppMotion.standard,
          // Seleccionada: sube un poco por encima de las demás.
          margin: EdgeInsets.only(bottom: selected ? 12 : 0),
          padding: const EdgeInsets.symmetric(vertical: 8),
          width: double.infinity,
          height: 68,
          decoration: BoxDecoration(
            color: selected ? palette.accentDeep : palette.cardElevated,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: selected
                  ? palette.accentDeep
                  : Theme.of(context).dividerColor,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.accentDeep.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
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
                height: 13,
                child: isToday
                    ? Text(
                        'Hoy',
                        style: context.textTheme.labelSmall?.copyWith(
                          color:
                              selected ? Colors.white : palette.accentDeep,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          ),
        ],
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
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: current ? Border.all(color: s.vivid, width: 1.8) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl),
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  bottom: 24,
                  child: Icon(
                    slot.icon,
                    size: 120,
                    color: s.vivid.withValues(alpha: 0.14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              slot.subject,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleLarge?.copyWith(
                                color: s.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: s.vivid,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 24,),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 15, color: s.inkMuted,),
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
                      const Spacer(),
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
                                style:
                                    context.textTheme.labelMedium?.copyWith(
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
              ],
            ),
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
      decoration: BoxDecoration(
        color: palette.cardElevated,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _AnimatedCup(),
          const SizedBox(height: 10),
          Text(
            slot.subject,
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${slot.start} – ${slot.end}',
            style: context.textTheme.bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Taza de café animada: vapor que sube y se desvanece, y un leve vaivén.
class _AnimatedCup extends StatefulWidget {
  const _AnimatedCup();

  @override
  State<_AnimatedCup> createState() => _AnimatedCupState();
}

class _AnimatedCupState extends State<_AnimatedCup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.palette.textMuted;
    return SizedBox(
      width: 90,
      height: 90,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          Widget steam(double phase, double dx) {
            final t = (_c.value + phase) % 1.0;
            return Positioned(
              left: 30 + dx,
              top: 26 - 22 * t,
              child: Opacity(
                opacity: math.sin(math.pi * t).clamp(0.0, 1.0) * 0.7,
                child: Transform.translate(
                  offset: Offset(math.sin(t * math.pi * 2) * 3, 0),
                  child: Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              steam(0, 0),
              steam(0.33, 12),
              steam(0.66, 24),
              Positioned(
                left: 13,
                top: 30 + math.sin(_c.value * math.pi * 2) * 1.5,
                child: Icon(Icons.free_breakfast_rounded,
                    size: 64, color: color,),
              ),
            ],
          );
        },
      ),
    );
  }
}
