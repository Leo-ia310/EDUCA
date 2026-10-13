import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../providers.dart';
import '../widgets/home_hero.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/home_schedule_section.dart';
import '../widgets/student_home_header.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final dataAsync = ref.watch(studentDashboardProvider);

    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async {
        ref.invalidate(studentDashboardProvider);
        await ref.read(studentDashboardProvider.future);
      },
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
          dataAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: SkeletonList(items: 5),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: ErrorStateView(message: '$e'),
            ),
            data: (data) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: HomeHero(
                name: user.displayFirstName,
                subtitle: data.gradeGroup.isEmpty
                    ? 'Sin salón asignado'
                    : data.gradeGroup,
              ),
            ),
          ),
          dataAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: StaggeredEntrance(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HomeScheduleSection(todaySchedule: data.todaySchedule),
                  const SizedBox(height: 24),
                  if (data.todaySchedule.isEmpty &&
                      data.subjects.isEmpty &&
                      data.tasks.isEmpty &&
                      data.grades.isEmpty) ...[
                    const EmptyState(
                      icon: Icons.school_outlined,
                      title: 'Sin datos reales todavía',
                      subtitle:
                          'Cuando el colegio asigne clases, horario, tareas o notas, aparecerán aquí.',
                    ),
                    const SizedBox(height: 24),
                  ],

                  const SectionHeader(title: 'Mi Espacio', accent: false),
                  const SizedBox(height: 12),
                  // Mi Espacio: tarjetas horizontales apiladas.
                  for (final t in [
                    _TileData(
                      icon: Icons.note_alt_rounded,
                      title: 'Tareas',
                      subtitle: 'Pendientes y entregadas',
                      color: context.palette.sun,
                      onTap: () => context.push(Routes.assignments),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.edit_rounded,
                          size: 64,
                          top: 4,
                          right: 40,
                          angle: 0.35,
                        ),
                        ArtItem.icon(
                          Icons.edit_rounded,
                          size: 48,
                          top: 50,
                          right: 0,
                          angle: -0.5,
                        ),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.school_rounded,
                      title: 'Pruebas',
                      subtitle: 'Exámenes y quizzes',
                      color: context.palette.coral,
                      onTap: () => context.push(Routes.exams),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.description_rounded,
                          size: 96,
                          top: 3,
                          right: 6,
                          angle: 0.12,
                        ),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.menu_book_rounded,
                      title: 'Materias',
                      subtitle: 'Tus materias y profesores',
                      color: context.palette.accent,
                      onTap: () => context.push(Routes.subjects),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.add_rounded,
                          size: 28,
                          top: 2,
                          right: 70,
                        ),
                        ArtItem.icon(
                          Icons.straighten_rounded,
                          size: 34,
                          top: 4,
                          right: 30,
                          angle: 0.6,
                        ),
                        ArtItem.icon(
                          Icons.edit_rounded,
                          size: 26,
                          top: 54,
                          right: 64,
                          angle: -0.4,
                        ),
                        ArtItem.icon(
                          Icons.polymer_rounded,
                          size: 30,
                          top: 50,
                          right: 14,
                        ),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.event_available_rounded,
                      title: 'Asistencia',
                      subtitle: 'Tu porcentaje del periodo',
                      color: context.palette.success,
                      onTap: () => context.push(Routes.myAttendance),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.check_rounded,
                          size: 96,
                          top: 3,
                          right: 8,
                        ),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.calendar_month_rounded,
                      title: 'Horario',
                      subtitle: 'Tu horario de clases',
                      color: context.palette.mint,
                      onTap: () => context.push(Routes.schedule),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.calendar_month_rounded,
                          size: 92,
                          top: 5,
                          right: 8,
                        ),
                      ]),
                    ),
                    _TileData(
                      icon: Icons.co_present_rounded,
                      title: 'Maestros',
                      subtitle: 'Tus Maestros',
                      color: context.palette.grape,
                      onTap: () => context.push(Routes.teachers),
                      art: const ArtCluster([
                        ArtItem.icon(
                          Icons.apple,
                          size: 92,
                          top: 5,
                          right: 8,
                        ),
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
