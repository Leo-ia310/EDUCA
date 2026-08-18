import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/quick_actions_sheet.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../attendance/presentation/widgets/sync_status_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../chat/providers.dart';
import '../../../notifications/providers.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/greeting_header.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  late Map<String, bool> _attendance = {
    for (final s in TeacherMockData.quickAttendance) s.name: s.present,
  };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.home,
        onTap: (item) => _handleNav(context, item),
      ),
      fab: EducaFab(
        onPressed: () => showQuickActionsSheet(
          context,
          title: 'Accesos rápidos',
          actions: const [
            QuickActionEntry(
              icon: Icons.add_task_rounded,
              label: 'Asignar nueva tarea',
              route: '${Routes.assignmentNew}?classId=101',
            ),
            QuickActionEntry(
              icon: Icons.how_to_reg_outlined,
              label: 'Tomar asistencia',
              route: Routes.attendance,
            ),
            QuickActionEntry(
              icon: Icons.grid_view_rounded,
              label: 'Libro de notas',
              route: Routes.gradebook,
            ),
            QuickActionEntry(
              icon: Icons.calendar_today_rounded,
              label: 'Ver horario',
              route: Routes.schedule,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardTopBar(
            onSettingsTap: () => context.go(Routes.profile),
            onNotificationsTap: () => context.push(Routes.alerts),
            onChatTap: () => context.push(Routes.chat),
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            chatBadge: ref.watch(totalUnreadProvider).asData?.value ?? 0,
          ),

          GreetingBanner(
            title: '¡Buen día, ${user.displayFirstName}!',
            subtitle:
                'Tienes ${TeacherMockData.pendingClasses} clases hoy y ${TeacherMockData.pendingGrading} tareas por calificar.',
          ),
          const SizedBox(height: 24),

          // Asistencia rápida
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Asistencia Rápida')),
              Text(
                '4° A · Mat',
                style: context.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              children: [
                for (final line in TeacherMockData.quickAttendance) ...[
                  _AttendanceTile(
                    name: line.name,
                    present: _attendance[line.name] ?? line.present,
                    onChanged: (v) =>
                        setState(() => _attendance[line.name] = v),
                  ),
                  if (line != TeacherMockData.quickAttendance.last)
                    Divider(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      height: 12,
                    ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => context.push(Routes.attendance),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5A11),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Tomar / Finalizar Pase'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SyncStatusBadge(compact: true),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => context.push(Routes.attendanceHistory),
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: const Text('Historial'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Mis clases
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Mis Clases')),
              GestureDetector(
                onTap: () => context.push(Routes.schedule),
                child: Text(
                  'Ver Horario',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: TeacherMockData.myClasses.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                if (i >= TeacherMockData.myClasses.length) {
                  return Container(
                    width: 160,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            color: palette.limeDeep, size: 28),
                        const SizedBox(height: 6),
                        const Text('Agregar clase',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }
                final c = TeacherMockData.myClasses[i];
                return Container(
                  width: 220,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: palette.cardContrast,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(c.icon, color: palette.lime, size: 28),
                      const Spacer(),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.room,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Tareas y exámenes
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push(Routes.assignments),
                  child: const SectionHeader(title: 'Tareas y\nExámenes'),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    context.push('${Routes.assignmentNew}?classId=101'),
                icon: const Icon(Icons.add),
                label: const Text('Asignar Nuevo'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.limeDeep,
                  foregroundColor: const Color(0xFF1E2218),
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in TeacherMockData.upcomingAssignments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => context.push(Routes.assignments),
                child: _AssignmentRow(item: t),
              ),
            ),
          const SizedBox(height: 16),

          // Calificaciones recientes
          const SectionHeader(title: 'Calificaciones Recientes'),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              children: [
                for (final g in TeacherMockData.recentGrades) ...[
                  _RecentGradeRow(item: g),
                  if (g != TeacherMockData.recentGrades.last)
                    Divider(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      height: 18,
                    ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.gradebook),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('Libro de notas'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleNav(BuildContext context, EducaNavItem item) {
    switch (item) {
      case EducaNavItem.profile:
        context.go(Routes.profile);
        break;
      case EducaNavItem.alerts:
        context.push(Routes.alerts);
        break;
      case EducaNavItem.schedule:
        context.push(Routes.schedule);
        break;
      case EducaNavItem.home:
        break;
    }
  }
}

class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({
    required this.name,
    required this.present,
    required this.onChanged,
  });

  final String name;
  final bool present;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(name: name, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Checkbox.adaptive(
          value: present,
          onChanged: (v) => onChanged(v ?? false),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          activeColor: context.palette.limeDeep,
          checkColor: const Color(0xFF1E2218),
        ),
      ],
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.item});
  final UpcomingAssignment item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = item.urgent
        ? palette.danger
        : item.completed
            ? palette.success
            : palette.warning;
    final chipLabel = item.urgent
        ? 'Urgente'
        : item.completed
            ? 'Completado'
            : '${item.delivered}/${item.total}';

    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.completed
                  ? Icons.check_circle_outline
                  : Icons.assignment_outlined,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item.meta,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chipLabel,
              style: context.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentGradeRow extends StatelessWidget {
  const _RecentGradeRow({required this.item});
  final RecentGrade item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pass = item.score >= 6;
    final color = pass ? palette.success : palette.danger;
    return Row(
      children: [
        UserAvatar(name: item.student, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.student,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(item.topic,
                  style: context.textTheme.bodySmall, maxLines: 1),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              item.score.toStringAsFixed(1),
              style: context.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(item.when, style: context.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
