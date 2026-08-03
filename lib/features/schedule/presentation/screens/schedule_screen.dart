import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_controller.dart';
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
    final user = ref.watch(authControllerProvider).user;
    final slots = ScheduleMock.byDay[_selectedDay] ?? const [];

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Horario'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (user != null) {
              context.go(user.activeRole.dashboardRoute);
            }
          },
        ),
      ),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.schedule,
        onTap: (item) {
          switch (item) {
            case EducaNavItem.home:
              if (user != null) context.go(user.activeRole.dashboardRoute);
              break;
            case EducaNavItem.alerts:
              context.push(Routes.alerts);
              break;
            case EducaNavItem.profile:
              context.go(Routes.profile);
              break;
            case EducaNavItem.schedule:
              break;
          }
        },
      ),
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
                      color: selected ? palette.limeDeep : palette.cardElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? palette.limeDeep
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
                                ? const Color(0xFF1E2218)
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
                                    ? const Color(0xFF1E2218)
                                    : palette.limeDeep)
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
                padding: const EdgeInsets.only(bottom: 12),
                child: _SlotCard(slot: slot),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});
  final ClassSlot slot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(
                slot.start,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                slot.end,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            width: 4,
            height: 54,
            decoration: BoxDecoration(
              color: slot.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: slot.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(slot.icon, color: slot.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.subject,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slot.teacher,
                  style: context.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 13, color: palette.textMuted),
                    const SizedBox(width: 3),
                    Text(
                      slot.room,
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
