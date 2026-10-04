import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/home_hero.dart';
import '../widgets/home_schedule_section.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/student_home_header.dart';


class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final data = ref.watch(teacherDashboardProvider).valueOrNull ??
        TeacherDashboardData.mock();

    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra superior azul full-bleed.
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
            child: HomeHero(
              name: user.displayFirstName,
              subtitle: 'Docente · ${data.myClasses.length} grupos',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HomeScheduleSection(),
                const SizedBox(height: 24),

                // Secciones principales como tarjetas.
                const SectionHeader(title: 'Mi Espacio', accent: false),
                const SizedBox(height: 12),
                for (final t in [
                  (
                    icon: Icons.how_to_reg_rounded,
                    title: 'Asistencia Rápida',
                    subtitle: 'Tomar y finalizar pase',
                    color: const Color(0xFF2FA869),
                    route: Routes.attendance,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.check_circle_rounded,
                          size: 64, top: 4, right: 40, angle: 0.2,),
                      ArtItem.icon(Icons.groups_rounded,
                          size: 48, top: 50, right: 0, angle: -0.3,),
                    ]),
                  ),
                  (
                    icon: Icons.class_rounded,
                    title: 'Mis clases',
                    subtitle: '${data.myClasses.length} clases asignadas',
                    color: const Color(0xFF4C8DF5),
                    route: Routes.myClasses,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.menu_book_rounded,
                          size: 64, top: 4, right: 40, angle: 0.3,),
                      ArtItem.icon(Icons.architecture_rounded,
                          size: 48, top: 50, right: 0, angle: -0.4,),
                    ]),
                  ),
                  (
                    icon: Icons.assignment_rounded,
                    title: 'Tareas y Exámenes',
                    subtitle: 'Por materia y vista general',
                    color: const Color(0xFFF3993E),
                    route: Routes.assignments,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.edit_rounded,
                          size: 64, top: 4, right: 40, angle: 0.35,),
                      ArtItem.icon(Icons.description_rounded,
                          size: 48, top: 50, right: 0, angle: -0.4,),
                    ]),
                  ),
                  (
                    icon: Icons.grade_rounded,
                    title: 'Calificaciones Recientes',
                    subtitle: 'Libro de notas',
                    color: const Color(0xFF9A6BE0),
                    route: Routes.gradebook,
                    art: const ArtCluster([
                      ArtItem.text('A+', size: 56, top: 6, right: 30, angle: -0.2),
                      ArtItem.icon(Icons.check_circle_rounded,
                          size: 44, top: 56, right: 0, angle: 0.2,),
                    ]),
                  ),
                  (
                    icon: Icons.groups_rounded,
                    title: 'Grupos',
                    subtitle: '${data.myClasses.length} grupos de trabajo',
                    color: const Color(0xFFE5484D),
                    route: Routes.workTeams,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.groups_2_rounded,
                          size: 64, top: 4, right: 40, angle: 0.25,),
                      ArtItem.icon(Icons.diversity_3_rounded,
                          size: 48, top: 50, right: 0, angle: -0.3,),
                    ]),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: HomeOptionCard(
                      icon: t.icon,
                      title: t.title,
                      subtitle: t.subtitle,
                      color: t.color,
                      art: t.art,
                      onTap: () => context.push(t.route),
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
