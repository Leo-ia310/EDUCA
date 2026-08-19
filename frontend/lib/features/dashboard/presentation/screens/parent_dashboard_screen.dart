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
import '../../../auth/presentation/auth_controller.dart';
import '../../../chat/providers.dart';
import '../../../notifications/providers.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/greeting_header.dart';

class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState
    extends ConsumerState<ParentDashboardScreen> {
  int _selectedChild = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();
    final childIndex =
        _selectedChild < data.children.length ? _selectedChild : 0;
    final child = data.children.isEmpty
        ? const ChildBrief('—')
        : data.children[childIndex];

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
              icon: Icons.calendar_today_rounded,
              label: 'Ver horario',
              route: Routes.schedule,
            ),
            QuickActionEntry(
              icon: Icons.credit_card_rounded,
              label: 'Pagos',
              route: '${Routes.payments}',
            ),
            QuickActionEntry(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Boletín',
              route: '${Routes.reports}',
            ),
            QuickActionEntry(
              icon: Icons.chat_bubble_outline,
              label: 'Nuevo mensaje',
              route: Routes.chatNew,
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
                    data.newNotices,
            chatBadge: ref.watch(totalUnreadProvider).asData?.value ?? 0,
          ),

          GreetingBanner(
            title: '¡Hola, ${user.displayFirstName}!',
            subtitle:
                'Tienes ${data.newNotices} avisos nuevos y ${data.monthEvents} eventos este mes.',
          ),
          const SizedBox(height: 24),

          // Mis Hijos
          const SectionHeader(title: 'Mis Hijos'),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: data.children.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                if (i >= data.children.length) {
                  return Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: palette.surfaceAlt,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Icon(Icons.add,
                            color: palette.textMuted, size: 28),
                      ),
                      const SizedBox(height: 6),
                      Text('Añadir',
                          style: context.textTheme.labelSmall
                              ?.copyWith(color: palette.textMuted)),
                    ],
                  );
                }
                final c = data.children[i];
                final selected = i == _selectedChild;
                return GestureDetector(
                  onTap: () => setState(() => _selectedChild = i),
                  child: Column(
                    children: [
                      UserAvatar(
                        name: c.name,
                        size: 60,
                        ringColor: selected ? palette.limeDeep : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Estado de Asistencia
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: palette.lime,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado de Asistencia',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF34401C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${data.attendancePercent.toStringAsFixed(0)}%',
                        style: context.textTheme.displaySmall?.copyWith(
                          color: const Color(0xFF1E2218),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${child.name} está al día',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF34401C),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2B5A11),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Eventos + Avisos
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.calendar_month_rounded,
                  iconBg: palette.info.withValues(alpha: 0.15),
                  iconColor: palette.info,
                  value: '${data.monthEvents}',
                  label: 'Eventos este mes',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.mark_email_unread_rounded,
                  iconBg: palette.warning.withValues(alpha: 0.15),
                  iconColor: palette.warning,
                  value: '${data.newNotices}',
                  label: 'Avisos nuevos',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Materias y Profesores')),
              GestureDetector(
                onTap: () => context.push(Routes.schedule),
                child: Text(
                  'Ver Todo',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in data.subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SubjectTeacherRow(item: s),
            ),
          const SizedBox(height: 16),

          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Actividad Reciente')),
              GestureDetector(
                onTap: () => context.push(Routes.assignments),
                child: Text(
                  'Ver Tareas',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final a in data.recentActivity)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => context.push(Routes.assignments),
                child: _ActivityCard(item: a),
              ),
            ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    '${Routes.reports}',
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Boletín'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('${Routes.payments}'),
                  icon: const Icon(Icons.credit_card_rounded),
                  label: const Text('Pagos'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => context.push(Routes.chat),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Contactar con Coordinación'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return EduCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectTeacherRow extends StatelessWidget {
  const _SubjectTeacherRow({required this.item});
  final ParentSubject item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.menu_book_rounded,
                color: palette.limeDeep, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(item.teacher, style: context.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => context.push(Routes.chat),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: palette.cardContrast,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});
  final ParentActivity item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.limeSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.tag,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (item.score.isNotEmpty)
                Text(
                  item.score,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: palette.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(item.timeAgo, style: context.textTheme.bodySmall),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 6,
              backgroundColor: palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(palette.limeDeep),
            ),
          ),
        ],
      ),
    );
  }
}
