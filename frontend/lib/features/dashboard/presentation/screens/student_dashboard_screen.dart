import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../widgets/home_schedule_section.dart';
import '../widgets/student_home_header.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();

    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra superior azul, separada del hero.
          StudentHomeHeader(
            brutal: true,
            name: user.displayFirstName,
            initials: user.displayFirstName.isNotEmpty
                ? user.displayFirstName.substring(0, 1).toUpperCase()
                : '?',
            avatarUrl: user.avatarUrl,
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            onNotificationsTap: () => context.go(Routes.alerts),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _StudentHero(
              name: user.displayFirstName,
              gradeGroup: data.gradeGroup,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: StaggeredEntrance(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HomeScheduleSection(),
                  const SizedBox(height: 24),

                  const SectionHeader(title: 'Acceso Rápido', accent: false),
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

    // Altura de la zona de la barra superior (ancho completo); debajo, el hero
    // se estrecha con margen lateral y esquinas inferiores convexas.
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
      width: double.infinity,
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(_backgroundFor(now.hour), fit: BoxFit.cover),
          // Velo oscuro: arriba (para la barra superior) y a la izquierda
          // (para el texto), sobre la ilustración.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black38, Colors.transparent],
                stops: [0, 0.3],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.black38, Colors.transparent],
                stops: [0, 0.75],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
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
                    fontWeight: FontWeight.w400,
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
    );
  }
}
