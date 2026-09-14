import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
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
      final start = DateUtilsX.hhmmToMinutes(data.todaySchedule[i].startTime);
      final end = DateUtilsX.hhmmToMinutes(data.todaySchedule[i].endTime);
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
      padding: const EdgeInsets.only(bottom: 100),
      onRefresh: () async => Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero de bienvenida (full-bleed, sin padding lateral).
          AppGreetingHeader(
            greeting: DateUtilsX.greetingForHour(now),
            name: user.displayFirstName,
            initials: user.displayFirstName.isNotEmpty
                ? user.displayFirstName.substring(0, 1).toUpperCase()
                : '?',
            // Sin fotos reales: avatar placeholder determinista por usuario
            // (DiceBear permite CORS, a diferencia de los servicios de rostros).
            avatarUrl: user.avatarUrl ??
                'https://api.dicebear.com/9.x/avataaars/png?seed=${user.id}',
            dateLabel: toBeginningOfSentenceCase(
              DateFormat("EEEE, d 'de' MMMM", 'es').format(now),
            ),
            chipIcon: Icons.assignment_turned_in_rounded,
            chipLabel: data.pendingTasks > 0
                ? 'Tienes ${data.pendingTasks} ${data.pendingTasks == 1 ? 'tarea' : 'tareas'} para hoy'
                : 'No tienes tareas para hoy',
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            onNotificationsTap: () => context.go(Routes.alerts),
            settingsMenu: const AccountSettingsMenu(circular: true),
          ),
          // Resto del contenido, con padding lateral y entrada escalonada.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPIs de un vistazo (promedio · asistencia · pendientes)
                DashboardStatStrip(
                  tiles: [
                    StatTile(
                      icon: Icons.star_rounded,
                      color: const Color(0xFF34C77A),
                      value: data.averageScore,
                      decimals: 1,
                      label: 'Promedio',
                    ),
                    StatTile(
                      icon: Icons.event_available_rounded,
                      color: const Color(0xFF4C8DF5),
                      value: data.attendanceRate * 100,
                      suffix: '%',
                      label: 'Asistencia',
                    ),
                    StatTile(
                      icon: Icons.assignment_late_rounded,
                      color: data.pendingTasks > 0
                          ? const Color(0xFFF3993E)
                          : const Color(0xFF34C77A),
                      value: data.pendingTasks.toDouble(),
                      label: 'Pendientes',
                    ),
                  ],
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
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  weekday,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.accentDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < data.todaySchedule.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            ScheduleItemRow(
              slot: data.todaySchedule[i],
              highlighted: i == currentIdx,
              badge: i == currentIdx
                  ? 'Ahora'
                  : i == nextIdx
                      ? _inLabel(
                          DateUtilsX.hhmmToMinutes(data.todaySchedule[i].startTime) - nowMin,
                        )
                      : null,
            ),
          ],
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
          ),
        ],
      ),
    );
  }
}

/// Etiqueta "En X min" / "En Yh Zm" para la próxima clase.
String _inLabel(int minutes) {
  if (minutes <= 0) return 'Ahora';
  if (minutes < 60) return 'En $minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'En $h h' : 'En ${h}h ${m}m';
}
