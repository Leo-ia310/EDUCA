import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../../shared/models/app_role.dart';
import '../../../admin/data/school_directory.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../widgets/home_hero.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/student_home_header.dart';

typedef _Tile = ({
  IconData icon,
  String title,
  String subtitle,
  Color color,
  String route,
  Widget art,
});

/// Home del director/administración: hero + tarjetas a los CRUD
/// institucionales ("Mi Espacio") y al control académico y financiero.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final dir = ref.watch(schoolDirectoryProvider);

    Widget art(IconData a, IconData b) => ArtCluster([
          ArtItem.icon(a, size: 64, top: 4, right: 40, angle: 0.25),
          ArtItem.icon(b, size: 48, top: 50, right: 0, angle: -0.3),
        ]);

    final space = <_Tile>[
      (
        icon: Icons.badge_rounded,
        title: 'Maestros',
        subtitle: '${dir.byRole(AppRole.teacher).length} maestros y sus clases',
        color: const Color(0xFF4C8DF5),
        route: Routes.manageTeachers,
        art: art(Icons.school_rounded, Icons.edit_note_rounded),
      ),
      (
        icon: Icons.backpack_rounded,
        title: 'Alumnos',
        subtitle: '${dir.byRole(AppRole.student).length} alumnos inscritos',
        color: const Color(0xFFF3993E),
        route: Routes.adminStudents,
        art: art(Icons.face_rounded, Icons.menu_book_rounded),
      ),
      (
        icon: Icons.family_restroom_rounded,
        title: 'Padres',
        subtitle: '${dir.byRole(AppRole.parent).length} padres y tutores',
        color: const Color(0xFF9A6BE0),
        route: Routes.adminParents,
        art: art(Icons.favorite_rounded, Icons.face_3_rounded),
      ),
      (
        icon: Icons.meeting_room_rounded,
        title: 'Salones',
        subtitle: '${dir.groups.length} salones y años',
        color: const Color(0xFF33B7A0),
        route: Routes.adminGroups,
        art: art(Icons.groups_rounded, Icons.apartment_rounded),
      ),
      (
        icon: Icons.menu_book_rounded,
        title: 'Clases',
        subtitle: '${dir.classes.length} clases y asignaciones',
        color: const Color(0xFF2FA869),
        route: Routes.adminClasses,
        art: art(Icons.calculate_rounded, Icons.science_rounded),
      ),
      (
        icon: Icons.admin_panel_settings_rounded,
        title: 'Roles y perfiles',
        subtitle: '${dir.people.length} perfiles registrados',
        color: const Color(0xFFE5484D),
        route: Routes.adminRoles,
        art: art(Icons.verified_user_rounded, Icons.key_rounded),
      ),
    ];

    final control = <_Tile>[
      (
        icon: Icons.grid_view_rounded,
        title: 'Notas',
        subtitle: 'Libro de calificaciones',
        color: const Color(0xFF4C8DF5),
        route: Routes.gradebook,
        art: const ArtCluster([
          ArtItem.text('A+', size: 56, top: 6, right: 30, angle: -0.2),
          ArtItem.icon(
            Icons.check_circle_rounded,
            size: 44,
            top: 56,
            right: 0,
            angle: 0.2,
          ),
        ]),
      ),
      (
        icon: Icons.payments_rounded,
        title: 'Pagos',
        subtitle: 'Recaudación y morosidad',
        color: const Color(0xFF2FA869),
        route: Routes.paymentsDunning,
        art: art(Icons.credit_card_rounded, Icons.receipt_long_rounded),
      ),
      (
        icon: Icons.picture_as_pdf_rounded,
        title: 'Boletines',
        subtitle: 'Boletín de cada alumno',
        color: const Color(0xFFF3993E),
        route: Routes.adminReportCards,
        art: art(Icons.description_rounded, Icons.workspace_premium_rounded),
      ),
    ];

    List<Widget> cards(List<_Tile> tiles) => [
          for (final t in tiles)
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
        ];

    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              subtitle: user.activeRole.label,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Mi Espacio', accent: false),
                const SizedBox(height: 12),
                ...cards(space),
                const SizedBox(height: 20),
                const SectionHeader(
                  title: 'Control Institucional',
                  accent: false,
                ),
                const SizedBox(height: 12),
                ...cards(control),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
