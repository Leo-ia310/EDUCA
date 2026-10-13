import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/dashboard_models.dart';

/// Sección "Horario" del home. Usa únicamente los slots reales recibidos desde
/// el dashboard; si no hay clases para hoy, muestra un estado vacío claro.
class HomeScheduleSection extends StatefulWidget {
  const HomeScheduleSection({
    super.key,
    required this.todaySchedule,
  });

  final List<ScheduleSlot> todaySchedule;

  @override
  State<HomeScheduleSection> createState() => _HomeScheduleSectionState();
}

class _HomeScheduleSectionState extends State<HomeScheduleSection> {
  static const _cardHeight = 226.0;
  static const _days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie'];

  late final int _todayIdx = _indexForToday();
  late int _selected = _todayIdx;
  late PageController _controller = _controllerFor(_selected);

  bool get _weekend => DateTime.now().weekday > 5;

  int _indexForToday() {
    final weekday = DateTime.now().weekday;
    if (weekday < 1) return 0;
    if (weekday > 5) return 4;
    return weekday - 1;
  }

  /// Fecha del día `i` (0 = lunes) de la semana en curso.
  DateTime _dateFor(int i) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: i));
  }

  List<ScheduleSlot> _slotsFor(int day) {
    if (day != _todayIdx || _weekend) return const [];
    return widget.todaySchedule;
  }

  /// Hoy arranca en la clase en curso (o la siguiente); otros días, en la 1.ª.
  PageController _controllerFor(int day) {
    var initial = 0;
    final slots = _slotsFor(day);
    if (day == _todayIdx && !_weekend && slots.isNotEmpty) {
      final now = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;
      final i = slots.indexWhere(
        (s) => nowMin < DateUtilsX.hhmmToMinutes(s.endTime),
      );
      if (i >= 0) initial = i;
    }
    return PageController(viewportFraction: 0.64, initialPage: initial);
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
  void didUpdateWidget(covariant HomeScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todaySchedule != widget.todaySchedule) {
      final old = _controller;
      _controller = _controllerFor(_selected);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slotsFor(_selected);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Horario', accent: false),
        const SizedBox(height: 6),
        SizedBox(
          height: 86,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _DayPill(
                    label: _days[i],
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
        SizedBox(
          height: _cardHeight,
          child: slots.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_rounded,
                  title: 'Sin clases para este día',
                  subtitle: 'Cuando exista horario real, aparecerá aquí.',
                )
              : Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) => OverflowBox(
                        maxWidth: c.maxWidth + 32,
                        minWidth: c.maxWidth + 32,
                        maxHeight: _cardHeight,
                        child: SizedBox(
                          height: _cardHeight,
                          width: c.maxWidth + 32,
                          child: PageView.builder(
                            key: ValueKey(_selected),
                            controller: _controller,
                            physics: const NeverScrollableScrollPhysics(),
                            clipBehavior: Clip.none,
                            itemCount: slots.length,
                            itemBuilder: (context, i) {
                              final slot = slots[i];
                              return _CarouselItem(
                                controller: _controller,
                                index: i,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: _ClassCard(
                                    slot: slot,
                                    current: _selected == _todayIdx &&
                                        !_weekend &&
                                        nowMin >=
                                            DateUtilsX.hhmmToMinutes(
                                              slot.startTime,
                                            ) &&
                                        nowMin <
                                            DateUtilsX.hhmmToMinutes(
                                              slot.endTime,
                                            ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    _CarouselArrows(
                      controller: _controller,
                      count: slots.length,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CarouselArrows extends StatelessWidget {
  const _CarouselArrows({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final i = page.round();
        void go(int to) => controller.animateToPage(
              to,
              duration: context.motion(AppMotion.base),
              curve: AppMotion.standard,
            );
        return Row(
          children: [
            _ArrowButton(
              icon: Icons.chevron_left_rounded,
              enabled: i > 0,
              onTap: () => go(i - 1),
            ),
            const Spacer(),
            _ArrowButton(
              icon: Icons.chevron_right_rounded,
              enabled: i < count - 1,
              onTap: () => go(i + 1),
            ),
          ],
        );
      },
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: AnimatedOpacity(
        duration: context.motion(AppMotion.fast),
        opacity: enabled ? 1 : 0.25,
        child: Material(
          color: palette.cardElevated,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, color: palette.accentDeep, size: 38),
            ),
          ),
        ),
      ),
    );
  }
}

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
        final page = controller.hasClients && controller.position.haveDimensions
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
    final fg = selected ? palette.onAccent : palette.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AnimatedContainer(
            duration: context.motion(AppMotion.base),
            curve: AppMotion.standard,
            margin: EdgeInsets.only(bottom: selected ? 10 : 0),
            padding: const EdgeInsets.symmetric(vertical: 6),
            width: double.infinity,
            height: 70,
            decoration: Brutal.decoration(
              context,
              color: selected ? palette.accentDeep : palette.cardElevated,
              radius: Radii.md,
              offset: 3,
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
                  style: context.textTheme.titleLarge?.copyWith(
                    color: selected ? palette.onAccent : null,
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
                            color: selected
                                ? palette.onAccent
                                : palette.accentDeep,
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
  final ScheduleSlot slot;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(slot.accent ?? subjectColor(slot.subject));
    final teacher = slot.teacher?.trim().isNotEmpty == true
        ? slot.teacher!.trim()
        : 'Docente por asignar';
    return BrutalBox(
      onTap: () => context.push(Routes.schedule),
      color: s.surface,
      radius: Radii.lg,
      clip: true,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              right: -22,
              bottom: 34,
              child: Icon(
                slot.icon ?? Icons.menu_book_rounded,
                size: 150,
                color: s.vivid.withValues(alpha: 0.14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
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
                      if (current)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: s.vivid,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            'Ahora',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 19,
                        color: s.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${slot.startTime} – ${slot.endTime}',
                        style: context.textTheme.titleSmall?.copyWith(
                          color: s.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (slot.room.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.meeting_room_rounded,
                          size: 18,
                          color: s.inkMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            slot.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: s.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(
                        color: Brutal.ink(context),
                        width: Brutal.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_circle_rounded,
                          size: 28,
                          color: s.vivid,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            teacher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF16202E),
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
    );
  }
}
