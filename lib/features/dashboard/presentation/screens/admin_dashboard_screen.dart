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
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/greeting_header.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.home,
        onTap: (i) {
          if (i == EducaNavItem.profile) context.go(Routes.profile);
        },
      ),
      fab: EducaFab(onPressed: () {}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardTopBar(
            onSettingsTap: () => context.go(Routes.profile),
            onNotificationsTap: () {},
            notificationsBadge: AdminMockData.systemAlerts,
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
                  'Resumen Institucional',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF1E2218),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _OverviewMini(
                        value:
                            '${AdminMockData.attendancePct.toStringAsFixed(1)}%',
                        label: 'Asistencia hoy',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OverviewMini(
                        value:
                            AdminMockData.institutionalAvg.toStringAsFixed(1),
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
            onTap: () {},
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.event_outlined,
            label: 'Crear Evento',
            variant: QuickActionVariant.surface,
            onTap: () {},
          ),
          const SizedBox(height: 10),
          QuickActionButton(
            icon: Icons.schedule_outlined,
            label: 'Modificar Horarios',
            variant: QuickActionVariant.surface,
            onTap: () {},
          ),
          const SizedBox(height: 24),

          // Anuncios recientes
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Anuncios Recientes')),
              GestureDetector(
                onTap: () {},
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
          for (final a in AdminMockData.announcements)
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
                onTap: () {},
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
                for (final t in AdminMockData.teachers) ...[
                  _TeacherRow(item: t),
                  if (t != AdminMockData.teachers.last)
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
                child: _AdminStatCard(
                  value: '${AdminMockData.totalStudents}',
                  label: 'Total estudiantes',
                  icon: Icons.people_outline,
                  color: palette.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminStatCard(
                  value: '${AdminMockData.activeTeachers}',
                  label: 'Docentes activos',
                  icon: Icons.badge_outlined,
                  color: palette.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AdminStatCard(
                  value: '${AdminMockData.upcomingEvents}',
                  label: 'Eventos próximos',
                  icon: Icons.event_available_outlined,
                  color: palette.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminStatCard(
                  value: '${AdminMockData.systemAlerts}',
                  label: 'Alertas sistema',
                  icon: Icons.warning_amber_outlined,
                  color: palette.danger,
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
                color: palette.limeDeep, size: 20),
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

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return EduCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.textTheme.bodySmall),
        ],
      ),
    );
  }
}
