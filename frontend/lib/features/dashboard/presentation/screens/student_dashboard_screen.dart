import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/quick_actions_sheet.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/section_nav_card.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../../profile/presentation/widgets/account_settings_menu.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/classmates_strip.dart';
import '../widgets/greeting_header.dart';
import '../widgets/schedule_item.dart';
import '../widgets/stat_strip.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final institution = ref.watch(authControllerProvider).institution;
    final palette = context.palette;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data =
        ref.watch(studentDashboardProvider).valueOrNull ??
            StudentDashboardData.mock();

    // Estado del horario respecto a la hora actual: clase en curso y siguiente.
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int? currentIdx;
    int? nextIdx;
    for (var i = 0; i < data.todaySchedule.length; i++) {
      final start = _toMinutes(data.todaySchedule[i].startTime);
      final end = _toMinutes(data.todaySchedule[i].endTime);
      if (nowMin >= start && nowMin < end) {
        currentIdx = i;
      } else if (start > nowMin && nextIdx == null) {
        nextIdx = i;
      }
    }
    // Etiqueta de fecha real (día de la semana capitalizado).
    final weekday = toBeginningOfSentenceCase(
      DateFormat('EEEE', 'es').format(now),
    );

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      onRefresh: () async => Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: EducaBottomNav(
        current: EducaNavItem.home,
        onTap: (item) => goToEducaTab(
          context,
          item: item,
          current: EducaNavItem.home,
          homeRoute: user.activeRole.dashboardRoute,
        ),
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
              icon: Icons.assignment_outlined,
              label: 'Mis tareas',
              route: Routes.assignments,
            ),
            QuickActionEntry(
              icon: Icons.grade_outlined,
              label: 'Mis notas',
              route: Routes.grades,
            ),
            QuickActionEntry(
              icon: Icons.chat_bubble_outline,
              label: 'Nuevo mensaje',
              route: Routes.chatNew,
            ),
          ],
        ),
      ),
      child: StaggeredEntrance(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardTopBar(
            settingsMenu: const AccountSettingsMenu(boxed: true),
            onNotificationsTap: () => context.go(Routes.alerts),
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
          ),

          // Saludo (consciente de la hora del día)
          GreetingBanner(
            title: '${_greeting(now)}, ${user.displayFirstName}',
            subtitle:
                'Tienes ${data.pendingTasks} tareas pendientes para hoy.',
            institutionName: institution?.name ?? 'Colegio Educa360',
            // Eslogan de ejemplo (placeholder, aún no viene del backend).
            slogan: 'Aprender hoy, liderar mañana.',
            crest: const _SchoolCrest(),
          ),
          const SizedBox(height: 16),

          // KPIs de un vistazo (promedio · asistencia · pendientes)
          DashboardStatStrip(
            average: data.averageScore,
            attendanceRate: data.attendanceRate,
            pendingTasks: data.pendingTasks,
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
                  weekday,
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
                for (var i = 0; i < data.todaySchedule.length; i++) ...[
                  if (i > 0 && currentIdx != i && currentIdx != i - 1)
                    Divider(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      height: 1,
                    ),
                  ScheduleItemRow(
                    slot: data.todaySchedule[i],
                    highlighted: i == currentIdx,
                    badge: i == currentIdx
                        ? 'Ahora'
                        : i == nextIdx
                            ? _inLabel(
                                _toMinutes(data.todaySchedule[i].startTime) -
                                    nowMin,
                              )
                            : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Compañeros
          const SectionHeader(title: 'Compañeros'),
          const SizedBox(height: 12),
          ClassmatesStrip(
            names: data.classmates,
            extraCount: data.classmatesExtra,
          ),
          const SizedBox(height: 24),

          // Materias — tarjeta de acceso a la lista completa.
          SectionNavCard(
            icon: Icons.menu_book_rounded,
            title: 'Materias',
            subtitle: 'Todas tus materias y su progreso',
            color: const Color(0xFF4C8DF5),
            badge: '${data.subjects.length} materias',
            onTap: () => context.push(Routes.subjects),
          ),
          const SizedBox(height: 14),

          // Tareas — tarjeta de acceso al feed de tareas.
          SectionNavCard(
            icon: Icons.note_alt_rounded,
            title: 'Tareas',
            subtitle: 'Tus entregas y actividades',
            color: const Color(0xFFF3993E),
            badge: data.pendingTasks > 0
                ? '${data.pendingTasks} pendientes'
                : 'Al día',
            onTap: () => context.push(Routes.assignments),
          ),
          const SizedBox(height: 14),

          // Notas — tarjeta de acceso al boletín/calificaciones.
          SectionNavCard(
            icon: Icons.edit_rounded,
            title: 'Notas',
            subtitle: 'Boletín y calificaciones',
            color: const Color(0xFF9A6BE0),
            badge: 'Prom. ${data.averageScore.toStringAsFixed(1)}',
            onTap: () => context.push(Routes.grades),
          ),
        ],
      ),
    );
  }
}

/// Escudo/emblema del colegio (placeholder inventado, para previsualizar).
class _SchoolCrest extends StatelessWidget {
  const _SchoolCrest();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.shield_rounded, size: 60, color: Color(0xFF2B5A11)),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Icon(
              Icons.auto_stories_rounded,
              size: 22,
              color: context.palette.lime,
            ),
          ),
        ],
      ),
    );
  }
}

/// Saludo según la hora del día.
String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

/// Convierte "HH:MM" en minutos desde medianoche.
int _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return h * 60 + m;
}

/// Etiqueta "En X min" / "En Yh Zm" para la próxima clase.
String _inLabel(int minutes) {
  if (minutes <= 0) return 'Ahora';
  if (minutes < 60) return 'En $minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'En $h h' : 'En ${h}h ${m}m';
}
