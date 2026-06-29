import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/classmates_strip.dart';
import '../widgets/grades_block.dart';
import '../widgets/greeting_header.dart';
import '../widgets/schedule_item.dart';
import '../widgets/subject_card.dart';
import '../widgets/task_card.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      onRefresh: () async => Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.home,
        onTap: (item) => _handleNav(context, item),
      ),
      fab: EducaFab(onPressed: () {}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardTopBar(
            onSettingsTap: () => context.go(Routes.profile),
            onNotificationsTap: () {},
            notificationsBadge: 2,
          ),

          // Saludo
          GreetingBanner(
            title: '¡Hola, ${user.displayFirstName}!',
            subtitle:
                'Tienes ${StudentMockData.pendingTasks} tareas pendientes para hoy.',
          ),
          const SizedBox(height: 24),

          // Horario de hoy
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Horario de Hoy')),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.limeSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Lunes',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EduCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < StudentMockData.todaySchedule.length; i++) ...[
                  if (i > 0)
                    Divider(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      height: 1,
                    ),
                  ScheduleItemRow(slot: StudentMockData.todaySchedule[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Compañeros
          const SectionHeader(title: 'Compañeros'),
          const SizedBox(height: 12),
          ClassmatesStrip(
            names: StudentMockData.classmates,
            extraCount: StudentMockData.classmatesExtra,
          ),
          const SizedBox(height: 24),

          // Materias inscritas
          const SectionHeader(title: 'Materias Inscritas'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < StudentMockData.subjects.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                    child:
                        SubjectProgressCard(subject: StudentMockData.subjects[i])),
              ],
            ],
          ),
          const SizedBox(height: 24),

          // Mis Tareas
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Mis Tareas')),
              GestureDetector(
                onTap: () => context.push(Routes.assignments),
                child: Text(
                  'Ver todas',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final task in StudentMockData.tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => context.push(Routes.assignments),
                child: TaskRow(task: task),
              ),
            ),
          const SizedBox(height: 16),

          // Mis Notas (bloque oscuro)
          GradesBlock(
            grades: StudentMockData.grades,
            average: StudentMockData.averageScore,
            onDownload: () {},
          ),
        ],
      ),
    );
  }

  void _handleNav(BuildContext context, EducaNavItem item) {
    switch (item) {
      case EducaNavItem.home:
        break;
      case EducaNavItem.schedule:
        // TODO: navigate to /schedule
        break;
      case EducaNavItem.alerts:
        // TODO: navigate to /alerts
        break;
      case EducaNavItem.profile:
        context.go(Routes.profile);
        break;
    }
  }
}
