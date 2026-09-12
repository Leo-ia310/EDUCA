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
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../../profile/presentation/widgets/account_settings_menu.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/greeting_header.dart';
import '../widgets/stat_strip.dart';
import 'announcement_detail_screen.dart';

// Tarjeta clara neutra para listas funcionales (maestros).
const Color _panelCard = Color(0xFFEFF1F6);
const Color _panelInk = Color(0xFF232A33);

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(authControllerProvider).user!;
    final data = ref.watch(adminDashboardProvider).valueOrNull ??
        AdminDashboardData.mock();
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
              icon: Icons.event_outlined,
              label: 'Crear evento',
              route: Routes.eventNew,
            ),
            QuickActionEntry(
              icon: Icons.school_outlined,
              label: 'Asignar maestros',
              route: Routes.manageTeachers,
            ),
            QuickActionEntry(
              icon: Icons.schedule_outlined,
              label: 'Modificar horarios',
              route: Routes.schedule,
            ),
            QuickActionEntry(
              icon: Icons.payments_outlined,
              label: 'Recaudación',
              route: Routes.paymentsDunning,
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
            chipIcon: Icons.insights_rounded,
            chipLabel:
                '${data.attendancePct.toStringAsFixed(0)}% asistencia hoy',
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ??
                    data.systemAlerts,
            onNotificationsTap: () => context.go(Routes.alerts),
            settingsMenu: const AccountSettingsMenu(circular: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen institucional (2 franjas de KPIs).
                const SectionHeader(title: 'Resumen Institucional'),
                const SizedBox(height: 10),
                DashboardStatStrip(
                  tiles: [
                    StatTile(
                      icon: Icons.event_available_rounded,
                      color: const Color(0xFF34C77A),
                      value: data.attendancePct,
                      suffix: '%',
                      label: 'Asistencia',
                    ),
                    StatTile(
                      icon: Icons.star_rounded,
                      color: const Color(0xFF4C8DF5),
                      value: data.institutionalAvg,
                      decimals: 1,
                      label: 'Promedio',
                    ),
                    StatTile(
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF9A6BE0),
                      value: data.totalStudents.toDouble(),
                      label: 'Estudiantes',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DashboardStatStrip(
                  tiles: [
                    StatTile(
                      icon: Icons.badge_rounded,
                      color: const Color(0xFF33B7A0),
                      value: data.activeTeachers.toDouble(),
                      label: 'Docentes',
                    ),
                    StatTile(
                      icon: Icons.event_rounded,
                      color: const Color(0xFFF3993E),
                      value: data.upcomingEvents.toDouble(),
                      label: 'Eventos',
                    ),
                    StatTile(
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFE5484D),
                      value: data.systemAlerts.toDouble(),
                      label: 'Alertas',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Accesos rápidos (grid pastel de 2 columnas)
                const SectionHeader(title: 'Gestión'),
                const SizedBox(height: 8),
                _QuickActionsGrid(
                  actions: [
                    _AdminAction(
                      Icons.school_outlined,
                      'Asignar Maestros',
                      const Color(0xFF4C8DF5),
                      () => context.push(Routes.manageTeachers),
                    ),
                    _AdminAction(
                      Icons.event_outlined,
                      'Crear Evento',
                      const Color(0xFF34C77A),
                      () => context.push(Routes.eventNew),
                    ),
                    _AdminAction(
                      Icons.schedule_outlined,
                      'Modificar Horarios',
                      const Color(0xFF8A5CF6),
                      () => context.push(Routes.schedule),
                    ),
                    _AdminAction(
                      Icons.grid_view_rounded,
                      'Libro de notas',
                      const Color(0xFFF3993E),
                      () => context.push(Routes.gradebook),
                    ),
                    _AdminAction(
                      Icons.payments_outlined,
                      'Recaudación',
                      const Color(0xFFEC6A9C),
                      () => context.push(Routes.paymentsDunning),
                    ),
                    _AdminAction(
                      Icons.terminal_rounded,
                      'Panel de desarrollador',
                      const Color(0xFF33B7A0),
                      () => context.push(Routes.developer),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Anuncios recientes
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Anuncios Recientes'),
                    ),
                    GestureDetector(
                      onTap: () => context.push(Routes.announcements),
                      child: Text(
                        'Ver todos',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: palette.limeDeep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final a in data.announcements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OpenCard(
                      closed: (context, open) => GestureDetector(
                        onTap: open,
                        behavior: HitTestBehavior.opaque,
                        child: _AnnouncementRow(item: a),
                      ),
                      open: (context) =>
                          AnnouncementDetailScreen(announcement: a),
                    ),
                  ),
                const SizedBox(height: 16),

                // Maestros activos
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Maestros Activos'),
                    ),
                    GestureDetector(
                      onTap: () => context.push(Routes.manageTeachers),
                      child: Text(
                        'Gestionar',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: palette.limeDeep,
                          fontWeight: FontWeight.w700,
                        ),
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
                      for (final t in data.teachers) ...[
                        _TeacherRow(item: t),
                        if (t != data.teachers.last)
                          Divider(
                            color: _panelInk.withValues(alpha: 0.10),
                            height: 14,
                          ),
                      ],
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


class _AdminAction {
  const _AdminAction(this.icon, this.label, this.accent, this.onTap);
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
}

/// Grid de accesos rápidos en 2 columnas con altura pareja por fila.
class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.actions});
  final List<_AdminAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < actions.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < actions.length ? 10 : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _ActionTile(action: actions[i])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < actions.length
                        ? _ActionTile(action: actions[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tile de acceso rápido del admin, estilo pastel.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final _AdminAction action;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(action.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                      BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                  child: Icon(action.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w700,
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

/// Fila de anuncio, estilo pastel del panel.
class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow({required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(subjectColor(item.title));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: const Icon(
              Icons.campaign_rounded,
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
                  style: context.textTheme.titleSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherRow extends StatelessWidget {
  const _TeacherRow({required this.item});
  final AdminTeacher item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(name: item.name, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: context.textTheme.titleSmall?.copyWith(
                  color: _panelInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                item.subject,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: _panelInk.withValues(alpha: 0.62)),
              ),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF2FA869),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
