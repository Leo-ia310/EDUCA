import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/quick_action_button.dart';
import '../../../../core/widgets/quick_actions_sheet.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../chat/providers.dart';
import '../../../notifications/providers.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/greeting_header.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(authControllerProvider).user!;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(adminDashboardProvider).valueOrNull ??
        AdminDashboardData.mock();
    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.home,
        onTap: (i) {
          if (i == EducaNavItem.profile) context.go(Routes.profile);
          if (i == EducaNavItem.alerts) context.push(Routes.alerts);
          if (i == EducaNavItem.schedule) context.push(Routes.schedule);
        },
      ),
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
          DashboardTopBar(
            onSettingsTap: () => context.go(Routes.profile),
            onNotificationsTap: () => context.push(Routes.alerts),
            onChatTap: () => context.push(Routes.chat),
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ??
                    data.systemAlerts,
            chatBadge: ref.watch(totalUnreadProvider).asData?.value ?? 0,
          ),

          // Resumen institucional verde
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.lime,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Hola, ${user.displayFirstName}!',
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF1E2218),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Resumen Institucional',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF34401C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _OverviewMini(
                        value:
                            '${data.attendancePct.toStringAsFixed(1)}%',
                        label: 'Asistencia hoy',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OverviewMini(
                        value:
                            data.institutionalAvg.toStringAsFixed(1),
                        label: 'Promedio institucional',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Acciones rápidas
          QuickActionButton(
            icon: Icons.school_outlined,
            label: 'Asignar Maestros',
            onTap: () => context.push(Routes.manageTeachers),
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.event_outlined,
            label: 'Crear Evento',
            variant: QuickActionVariant.surface,
            onTap: () => context.push(Routes.eventNew),
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.schedule_outlined,
            label: 'Modificar Horarios',
            variant: QuickActionVariant.surface,
            onTap: () => context.push(Routes.schedule),
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.grid_view_rounded,
            label: 'Libro de notas',
            variant: QuickActionVariant.surface,
            onTap: () => context.push(Routes.gradebook),
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.payments_outlined,
            label: 'Recaudación',
            variant: QuickActionVariant.surface,
            onTap: () => context.push(Routes.paymentsDunning),
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.terminal_rounded,
            label: 'Panel de desarrollador',
            variant: QuickActionVariant.surface,
            onTap: () => context.push(Routes.developer),
          ),
          const SizedBox(height: 24),

          // Anuncios recientes
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Anuncios Recientes')),
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
              child: _AnnouncementRow(item: a),
            ),
          const SizedBox(height: 16),

          // Maestros activos
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Maestros Activos')),
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
          EduCard(
            child: Column(
              children: [
                for (final t in data.teachers) ...[
                  _TeacherRow(item: t),
                  if (t != data.teachers.last)
                    Divider(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      height: 14,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats inferiores
          Row(
            children: [
              Expanded(
                child: StatCard(
                  value: '${data.totalStudents}',
                  label: 'Total estudiantes',
                  icon: Icons.people_outline,
                  accent: palette.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  value: '${data.activeTeachers}',
                  label: 'Docentes activos',
                  icon: Icons.badge_outlined,
                  accent: palette.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  value: '${data.upcomingEvents}',
                  label: 'Eventos próximos',
                  icon: Icons.event_available_outlined,
                  accent: palette.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  value: '${data.systemAlerts}',
                  label: 'Alertas sistema',
                  icon: Icons.warning_amber_outlined,
                  accent: palette.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMini extends StatelessWidget {
  const _OverviewMini({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.textTheme.titleLarge?.copyWith(
              color: const Color(0xFF1E2218),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: const Color(0xFF34401C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  const _AnnouncementRow({required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.campaign_outlined,
                color: palette.limeDeep, size: 20,),
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
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: context.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(item.subject, style: context.textTheme.bodySmall),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: context.palette.success,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

