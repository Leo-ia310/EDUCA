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
import 'activity_detail_screen.dart';

class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  int _selectedChild = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();
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
              icon: Icons.calendar_today_rounded,
              label: 'Ver horario',
              route: Routes.schedule,
            ),
            QuickActionEntry(
              icon: Icons.credit_card_rounded,
              label: 'Pagos',
              route: Routes.payments,
            ),
            QuickActionEntry(
              icon: Icons.picture_as_pdf_rounded,
              label: 'Boletín',
              route: Routes.reports,
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
            chipIcon: Icons.notifications_active_rounded,
            chipLabel:
                '${data.newNotices} avisos · ${data.monthEvents} eventos este mes',
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ??
                    data.newNotices,
            onNotificationsTap: () => context.go(Routes.alerts),
            settingsMenu: const AccountSettingsMenu(circular: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                              child: Icon(
                                Icons.add,
                                color: palette.textMuted,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Añadir',
                              style: context.textTheme.labelSmall
                                  ?.copyWith(color: palette.textMuted),
                            ),
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
                              ringColor: selected ? palette.accentDeep : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.labelMedium?.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // KPIs (asistencia · eventos · avisos)
                DashboardStatStrip(
                  tiles: [
                    StatTile(
                      icon: Icons.event_available_rounded,
                      color: const Color(0xFF34C77A),
                      value: data.attendancePercent,
                      suffix: '%',
                      label: 'Asistencia',
                    ),
                    StatTile(
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF4C8DF5),
                      value: data.monthEvents.toDouble(),
                      label: 'Eventos',
                    ),
                    StatTile(
                      icon: Icons.mark_email_unread_rounded,
                      color: const Color(0xFFF3993E),
                      value: data.newNotices.toDouble(),
                      label: 'Avisos',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Materias y Profesores
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Materias y Profesores'),
                    ),
                    GestureDetector(
                      onTap: () => context.push(Routes.schedule),
                      child: Text(
                        'Ver Todo',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: palette.accentDeep,
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

                // Actividad Reciente
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Actividad Reciente'),
                    ),
                    GestureDetector(
                      onTap: () => context.push(Routes.assignments),
                      child: Text(
                        'Ver Tareas',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: palette.accentDeep,
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
                    child: OpenCard(
                      closed: (context, open) => GestureDetector(
                        onTap: open,
                        behavior: HitTestBehavior.opaque,
                        child: _ActivityCard(item: a),
                      ),
                      open: (context) => ActivityDetailScreen(activity: a),
                    ),
                  ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(Routes.reports),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Boletín'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(Routes.payments),
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
          ),
        ],
      ),
    );
  }
}


/// Fila de materia + profesor, estilo pastel del panel.
class _SubjectTeacherRow extends StatelessWidget {
  const _SubjectTeacherRow({required this.item});
  final ParentSubject item;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(item.name));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: const Icon(
              Icons.menu_book_rounded,
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
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item.teacher,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: s.vivid,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push(Routes.chat),
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de actividad reciente, estilo pastel del panel.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});
  final ParentActivity item;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(item.tag.isEmpty ? item.title : item.tag));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: s.vivid.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  item.tag,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (item.score.isNotEmpty)
                Text(
                  item.score,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: context.textTheme.titleSmall?.copyWith(
              color: s.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.timeAgo,
            style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xs),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 6,
              backgroundColor: s.ink.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(s.vivid),
            ),
          ),
        ],
      ),
    );
  }
}
