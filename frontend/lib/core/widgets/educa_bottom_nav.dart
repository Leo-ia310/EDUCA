import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/providers.dart';
import '../../shared/models/app_role.dart';
import '../routing/route_paths.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'brutal.dart';

/// Una pestaña del bottom nav: ícono, etiqueta y ruta destino.
class EducaTab {
  const EducaTab({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

/// Pestañas del bottom nav según el rol. Inicio/Mensajes/Perfil son comunes;
/// las del medio cambian por rol.
List<EducaTab> navTabsForRole(AppRole role) {
  const messages = EducaTab(
    icon: Icons.chat_bubble_rounded,
    label: 'Mensajes',
    route: Routes.chat,
  );
  const profile = EducaTab(
    icon: Icons.person_rounded,
    label: 'Perfil',
    route: Routes.profile,
  );
  return switch (role) {
    AppRole.teacher => const [
        EducaTab(
          icon: Icons.home_rounded,
          label: 'Inicio',
          route: Routes.teacherDashboard,
        ),
        EducaTab(
          icon: Icons.calendar_today_rounded,
          label: 'Horario',
          route: Routes.schedule,
        ),
        EducaTab(
          icon: Icons.assignment_rounded,
          label: 'Tareas',
          route: Routes.assignments,
        ),
        messages,
        profile,
      ],
    AppRole.parent => const [
        EducaTab(
          icon: Icons.home_rounded,
          label: 'Inicio',
          route: Routes.parentDashboard,
        ),
        EducaTab(
          icon: Icons.payments_rounded,
          label: 'Pagos',
          route: Routes.payments,
        ),
        messages,
        profile,
      ],
    AppRole.admin || AppRole.coordinator || AppRole.director => const [
        EducaTab(
          icon: Icons.home_rounded,
          label: 'Inicio',
          route: Routes.adminDashboard,
        ),
        EducaTab(
          icon: Icons.groups_rounded,
          label: 'Maestros',
          route: Routes.manageTeachers,
        ),
        EducaTab(
          icon: Icons.campaign_rounded,
          label: 'Anuncios',
          route: Routes.announcements,
        ),
        messages,
        profile,
      ],
    AppRole.student => const [
        EducaTab(
          icon: Icons.home_rounded,
          label: 'Inicio',
          route: Routes.studentDashboard,
        ),
        EducaTab(
          icon: Icons.calendar_month_rounded,
          label: 'Calendario',
          route: Routes.calendar,
        ),
        messages,
        profile,
      ],
  };
}

/// Bottom nav flotante, consciente del rol: lee el rol del usuario y la ruta
/// actual para mostrar las pestañas correctas y resaltar la activa. El ítem
/// activo se dibuja en un círculo blanco flotante con notch cóncavo. Muestra
/// automáticamente el badge de no leídos sobre "Mensajes".
class EducaBottomNav extends ConsumerWidget {
  const EducaBottomNav({super.key});

  /// Color único de la barra (para todas las pestañas). Público para que otras
  /// superficies (p. ej. la barra superior del home) puedan igualarlo.
  static const Color barColor = Color(0xFF4C8DF5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role =
        ref.watch(authControllerProvider).user?.activeRole ?? AppRole.student;
    final tabs = navTabsForRole(role);
    final unread = ref.watch(totalUnreadProvider).asData?.value ?? 0;

    // Pestaña activa por coincidencia con la ruta actual (-1 si ninguna).
    final loc = GoRouterState.of(context).uri.path;
    var activeIndex = -1;
    for (var i = 0; i < tabs.length; i++) {
      final r = tabs[i].route;
      if (loc == r || loc.startsWith('$r/')) {
        activeIndex = i;
        break;
      }
    }

    return _BrutalNav(
      tabs: tabs,
      activeIndex: activeIndex,
      unread: unread,
    );
  }
}

/// Barra azul con borde grueso
/// y sombra dura; el ítem activo crece ligeramente y se rodea de un cuadrado
/// redondeado con borde grueso.
class _BrutalNav extends StatelessWidget {
  const _BrutalNav({
    required this.tabs,
    required this.activeIndex,
    required this.unread,
  });

  final List<EducaTab> tabs;
  final int activeIndex;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: BrutalBox(
            color: EducaBottomNav.barColor,
            radius: Radii.lg,
            child: SizedBox(
              height: 66,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _BrutalSlot(
                        icon: tabs[i].icon,
                        active: i == activeIndex,
                        badge: tabs[i].route == Routes.chat ? unread : 0,
                        onTap: () {
                          if (i != activeIndex) context.go(tabs[i].route);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrutalSlot extends StatelessWidget {
  const _BrutalSlot({
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Brutal.ink(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: context.motion(AppMotion.base),
              curve: AppMotion.standard,
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: active ? ink : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: AnimatedScale(
                scale: active ? 1.15 : 1,
                duration: context.motion(AppMotion.base),
                curve: AppMotion.standard,
                child: Icon(
                  icon,
                  size: 24,
                  color: active ? Colors.black : Colors.white,
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.palette.danger,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
