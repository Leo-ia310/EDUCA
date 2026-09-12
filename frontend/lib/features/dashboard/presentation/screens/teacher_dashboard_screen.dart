import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/open_card.dart';
import '../../../../core/widgets/quick_actions_sheet.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../attendance/presentation/widgets/sync_status_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../../profile/presentation/widgets/account_settings_menu.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/greeting_header.dart';
import '../widgets/stat_strip.dart';
import 'class_detail_screen.dart';

// Tarjeta clara neutra para listas funcionales (asistencia, calificaciones).
const Color _panelCard = Color(0xFFEFF1F6);
const Color _panelInk = Color(0xFF232A33);

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  final Map<String, bool> _attendance = {};

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;
    final data = ref.watch(teacherDashboardProvider).valueOrNull ??
        TeacherDashboardData.mock();
    for (final s in data.quickAttendance) {
      _attendance.putIfAbsent(s.name, () => s.present);
    }
    final now = DateTime.now();

    return AppScaffold(
      padding: const EdgeInsets.only(bottom: 100),
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      fab: EducaFab(
        onPressed: () => showQuickActionsSheet(
          context,
          title: 'Accesos rápidos',
          actions: const [
            QuickActionEntry(
              icon: Icons.add_task_rounded,
              label: 'Asignar nueva tarea',
              route: Routes.assignmentNew,
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
          // Hero de bienvenida (full-bleed).
          AppGreetingHeader(
            greeting: DateUtilsX.greetingForHour(now),
            name: user.displayFirstName,
            initials: user.displayFirstName.isNotEmpty
                ? user.displayFirstName.substring(0, 1).toUpperCase()
                : '?',
            dateLabel: toBeginningOfSentenceCase(
              DateFormat("EEEE, d 'de' MMMM", 'es').format(now),
            ),
            chipIcon: Icons.event_note_rounded,
            chipLabel:
                '${data.pendingClasses} clases hoy · ${data.pendingGrading} por calificar',
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            onNotificationsTap: () => context.go(Routes.alerts),
            settingsMenu: const AccountSettingsMenu(circular: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPIs
                DashboardStatStrip(
                  tiles: [
                    StatTile(
                      icon: Icons.event_note_rounded,
                      color: const Color(0xFF4C8DF5),
                      value: data.pendingClasses.toDouble(),
                      label: 'Clases hoy',
                    ),
                    StatTile(
                      icon: Icons.fact_check_rounded,
                      color: const Color(0xFFF3993E),
                      value: data.pendingGrading.toDouble(),
                      label: 'Por calificar',
                    ),
                    StatTile(
                      icon: Icons.groups_rounded,
                      color: const Color(0xFF9A6BE0),
                      value: data.myClasses.length.toDouble(),
                      label: 'Grupos',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Asistencia rápida
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Asistencia Rápida'),
                    ),
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _panelCard,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      for (final line in data.quickAttendance) ...[
                        _AttendanceTile(
                          name: line.name,
                          present: _attendance[line.name] ?? line.present,
                          onChanged: (v) =>
                              setState(() => _attendance[line.name] = v),
                        ),
                        if (line != data.quickAttendance.last)
                          Divider(
                            color: _panelInk.withValues(alpha: 0.10),
                            height: 18,
                          ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.push(Routes.attendance),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4C8DF5),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Tomar / Finalizar Pase'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SyncStatusBadge(compact: true),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () =>
                                context.push(Routes.attendanceHistory),
                            style: TextButton.styleFrom(
                              foregroundColor: _panelInk.withValues(alpha: 0.7),
                            ),
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
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: data.myClasses.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      if (i >= data.myClasses.length) {
                        return _AddClassCard(
                          onTap: () => context.push(Routes.schedule),
                        );
                      }
                      final c = data.myClasses[i];
                      return OpenCard(
                        borderRadius: 20,
                        open: (context) => ClassDetailScreen(teacherClass: c),
                        closed: (context, open) =>
                            _ClassCard(teacherClass: c, onTap: open),
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
                        child: const SectionHeader(title: 'Tareas y Exámenes'),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push(Routes.assignmentNew),
                      icon: const Icon(Icons.add),
                      label: const Text('Asignar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.limeDeep,
                        foregroundColor: const Color(0xFF1E2218),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final t in data.upcomingAssignments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AssignmentRow(
                      item: t,
                      onTap: () => context.push(Routes.assignments),
                    ),
                  ),
                const SizedBox(height: 16),

                // Calificaciones recientes
                const SectionHeader(title: 'Calificaciones Recientes'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _panelCard,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      for (final g in data.recentGrades) ...[
                        _RecentGradeRow(item: g),
                        if (g != data.recentGrades.last)
                          Divider(
                            color: _panelInk.withValues(alpha: 0.10),
                            height: 18,
                          ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(Routes.gradebook),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _panelInk,
                            side: BorderSide(
                              color: _panelInk.withValues(alpha: 0.25),
                            ),
                            minimumSize: const Size(0, 44),
                          ),
                          icon: const Icon(Icons.grid_view_rounded),
                          label: const Text('Libro de notas'),
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


/// Tarjeta de clase (Mis Clases) en estilo pastel del panel.
class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.teacherClass, required this.onTap});
  final TeacherClass teacherClass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(subjectColor(teacherClass.name));
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
              child: Icon(teacherClass.icon, color: Colors.white, size: 22),
            ),
            const Spacer(),
            Text(
              teacherClass.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                color: s.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              teacherClass.room,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta punteada "Agregar clase".
class _AddClassCard extends StatelessWidget {
  const _AddClassCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
            Icon(Icons.add_circle_outline, color: palette.limeDeep, size: 28),
            const SizedBox(height: 6),
            const Text('Agregar clase', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          UserAvatar(name: name, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: context.textTheme.titleSmall?.copyWith(
                color: _panelInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Checkbox.adaptive(
            value: present,
            onChanged: (v) => onChanged(v ?? false),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            side: BorderSide(color: _panelInk.withValues(alpha: 0.4), width: 2),
            activeColor: const Color(0xFF4C8DF5),
            checkColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// Fila de tarea/examen del docente, estilo pastel (tintada por estado).
class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.item, required this.onTap});
  final UpcomingAssignment item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.urgent
        ? const Color(0xFFE5484D)
        : item.completed
            ? const Color(0xFF2FA869)
            : const Color(0xFFF3993E);
    final chipLabel = item.urgent
        ? 'Urgente'
        : item.completed
            ? 'Completado'
            : '${item.delivered}/${item.total}';
    final s = pastelSurface(statusColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration:
                      BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                  child: Icon(
                    item.completed
                        ? Icons.check_circle_outline
                        : Icons.assignment_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.vivid.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    chipLabel,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
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

class _RecentGradeRow extends StatelessWidget {
  const _RecentGradeRow({required this.item});
  final RecentGrade item;

  @override
  Widget build(BuildContext context) {
    final pass = item.score >= 6;
    final color =
        pass ? const Color(0xFF2FA869) : const Color(0xFFD3453B);
    final inkMuted = _panelInk.withValues(alpha: 0.62);
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
                  color: _panelInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                item.topic,
                style: context.textTheme.bodySmall?.copyWith(color: inkMuted),
                maxLines: 1,
              ),
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
            Text(
              item.when,
              style: context.textTheme.labelSmall?.copyWith(color: inkMuted),
            ),
          ],
        ),
      ],
    );
  }
}
