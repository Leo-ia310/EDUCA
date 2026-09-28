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
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/schedule_item.dart';
import '../widgets/student_home_header.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
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
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra superior full-bleed (avatar + nombre a la izquierda,
          // acciones a la derecha), con fondo azul hasta el borde superior.
          StudentHomeHeader(
            name: user.displayFirstName,
            initials: user.displayFirstName.isNotEmpty
                ? user.displayFirstName.substring(0, 1).toUpperCase()
                : '?',
            avatarUrl: user.avatarUrl,
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            onNotificationsTap: () => context.go(Routes.alerts),
          ),
          // Hero full-bleed: pegado a la barra superior y a los laterales
          // (sin margen), la curva del panel lo solapa por debajo.
          _StudentHero(
            name: user.displayFirstName,
            gradeGroup: data.gradeGroup,
          ),
          // Panel del contenido: se monta sobre el hero con esquinas
          // superiores redondeadas (solape = radio), de modo que la curva
          // parezca del panel (cóncava) y no del hero.
          Transform.translate(
            offset: const Offset(0, -_panelRadius),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_panelRadius),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: StaggeredEntrance(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Horario de hoy
                  Row(
                    children: [
                      const Expanded(
                          child: SectionHeader(title: 'Horario de Hoy'),),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4,),
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
                                  DateUtilsX.hhmmToMinutes(
                                        data.todaySchedule[i].startTime,
                                      ) -
                                      nowMin,
                                )
                              : null,
                    ),
                  ],
                  const SizedBox(height: 24),

                  const SectionHeader(title: 'Acceso Rápido'),
                  const SizedBox(height: 12),
                  // Accesos rápidos: tarjetas horizontales apiladas.
                  for (final t in [
                    _TileData(
                      icon: Icons.note_alt_rounded,
                      title: 'Tareas',
                      subtitle: 'Pendientes y entregadas',
                      color: const Color(0xFFF3993E),
                      onTap: () => context.push(Routes.assignments),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.edit_rounded,
                            size: 64, top: 4, right: 40, angle: 0.35,),
                        ArtItem.icon(Icons.edit_rounded,
                            size: 48, top: 50, right: 0, angle: -0.5,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.school_rounded,
                      title: 'Pruebas',
                      subtitle: 'Exámenes y quizzes',
                      color: const Color(0xFFD65D6B),
                      onTap: () => context.push(Routes.exams),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.description_rounded,
                            size: 96, top: 3, right: 6, angle: 0.12,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.menu_book_rounded,
                      title: 'Materias',
                      subtitle: 'Tus materias y profesores',
                      color: const Color(0xFF4C8DF5),
                      onTap: () => context.push(Routes.subjects),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.add_rounded,
                            size: 28, top: 2, right: 70,),
                        ArtItem.icon(Icons.straighten_rounded,
                            size: 34, top: 4, right: 30, angle: 0.6,),
                        ArtItem.icon(Icons.edit_rounded,
                            size: 26, top: 54, right: 64, angle: -0.4,),
                        ArtItem.icon(Icons.polymer_rounded,
                            size: 30, top: 50, right: 14,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.grade_rounded,
                      title: 'Notas',
                      subtitle: 'Calificaciones y promedio',
                      color: const Color(0xFF9A6BE0),
                      onTap: () => context.push(Routes.grades),
                      art: const ArtCluster([
                        ArtItem.text('A+', size: 68, top: 17, right: 4),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.event_available_rounded,
                      title: 'Asistencia',
                      subtitle: 'Tu porcentaje del periodo',
                      color: const Color(0xFF34C77A),
                      onTap: () => context.push(Routes.myAttendance),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.check_rounded,
                            size: 96, top: 3, right: 8,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.calendar_month_rounded,
                      title: 'Horario',
                      subtitle: 'Tu horario de clases',
                      color: const Color(0xFF33B7A0),
                      onTap: () => context.push(Routes.schedule),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.calendar_month_rounded,
                            size: 92, top: 5, right: 8,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.groups_rounded,
                      title: 'Compañeros',
                      subtitle: 'Tus compañeros de grupo',
                      color: const Color(0xFFEC6A9C),
                      onTap: () => context.push(Routes.classmates),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.person_rounded,
                            size: 96, top: 3, right: 8,),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.co_present_rounded,
                      title: 'Maestros',
                      subtitle: 'Tus maestros y contacto',
                      color: const Color(0xFF7C6AE0),
                      onTap: () => context.push(Routes.teachers),
                      art: const ArtCluster([
                        ArtItem.icon(Icons.apple,
                            size: 92, top: 5, right: 8,),
                      ]),
                    ),
                  ]) ...[
                    HomeOptionCard(
                      icon: t.icon,
                      title: t.title,
                      subtitle: t.subtitle,
                      color: t.color,
                      art: t.art,
                      onTap: t.onTap,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

/// Datos de una tarjeta de acceso rápido del home.
class _TileData {
  const _TileData({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.art,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Widget? art;
  final VoidCallback? onTap;
}

/// Hero de bienvenida del home: saludo + nombre + grado/grupo alineados a la
/// izquierda, sobre una ilustración de fondo (mañana/tarde/noche) según la
/// hora del día.
class _StudentHero extends StatelessWidget {
  const _StudentHero({
    required this.name,
    required this.gradeGroup,
  });

  final String name;
  final String gradeGroup;

  static String _backgroundFor(int hour) {
    if (hour < 12) return 'assets/images/hero_sky_morning.png';
    if (hour < 19) return 'assets/images/hero_sky_afternoon.png';
    return 'assets/images/hero_sky_night.png';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = DateUtilsX.greetingForHour(now);
    final textShadows = [
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
    ];

    return DecoratedBox(
      // Rellena de azul (mismo tono que la barra superior) las esquinas que
      // el radio del hero deja al descubierto, para que no se vea blanco.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EducaBottomNav.barColor, Color(0xFF3B74D6)],
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SizedBox(
          width: double.infinity,
          height: 380,
          child: Stack(
            fit: StackFit.expand,
          children: [
            Image.asset(_backgroundFor(now.hour), fit: BoxFit.cover),
            // Velo oscuro a la izquierda para que el texto sea legible sobre
            // la ilustración.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black45, Colors.transparent],
                  stops: [0, 0.75],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 20, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    greeting,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2.2,
                      shadows: textShadows,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      shadows: textShadows,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gradeGroup,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                      shadows: textShadows,
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Radio de la curva con que el panel se monta sobre la barra azul (cóncava).
const double _panelRadius = 24;

/// Etiqueta "En X min" / "En Yh Zm" para la próxima clase.
String _inLabel(int minutes) {
  if (minutes <= 0) return 'Ahora';
  if (minutes < 60) return 'En $minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'En $h h' : 'En ${h}h ${m}m';
}
