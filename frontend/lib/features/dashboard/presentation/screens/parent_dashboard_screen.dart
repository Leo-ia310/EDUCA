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
import '../widgets/home_tile_card.dart';
import '../widgets/student_home_header.dart';

class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();

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
                ref.watch(notificationsUnreadProvider).asData?.value ??
                    data.newNotices,
            onNotificationsTap: () => context.go(Routes.alerts),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: HomeHero(
              name: user.displayFirstName,
              subtitle: 'Familia',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: StaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Mi Espacio', accent: false),
                const SizedBox(height: 12),
                for (final t in [
                  (
                    icon: Icons.family_restroom_rounded,
                    title: 'Mis Hijos',
                    subtitle: data.children.map((c) => c.name).join(', '),
                    color: const Color(0xFF4C8DF5),
                    route: Routes.parentChildren as String?,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.face_rounded,
                          size: 64, top: 4, right: 40, angle: 0.2,),
                      ArtItem.icon(Icons.face_3_rounded,
                          size: 48, top: 50, right: 0, angle: -0.3,),
                    ]),
                  ),
                  (
                    icon: Icons.credit_card_rounded,
                    title: 'Pagos',
                    subtitle: 'Cuotas y recibos',
                    color: const Color(0xFF2FA869),
                    route: Routes.payments as String?,
                    art: const ArtCluster([
                      ArtItem.icon(Icons.payments_rounded,
                          size: 64, top: 4, right: 40, angle: 0.2,),
                      ArtItem.icon(Icons.receipt_long_rounded,
                          size: 48, top: 50, right: 0, angle: -0.3,),
                    ]),
                  ),
                  (
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'Boletín',
                    subtitle: 'Notas por periodo',
                    color: const Color(0xFFE5484D),
                    route: Routes.reports as String?,
                    art: const ArtCluster([
                      ArtItem.text('A+', size: 56, top: 6, right: 30, angle: -0.2),
                      ArtItem.icon(Icons.description_rounded,
                          size: 44, top: 56, right: 0, angle: 0.2,),
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
                      onTap: () {
                        final r = t.route;
                        if (r != null) context.push(r);
                      },
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
