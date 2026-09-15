import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/providers.dart';
import '../../shared/models/app_role.dart';
import '../routing/route_paths.dart';
import '../theme/app_theme.dart';

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
          icon: Icons.notifications_rounded,
          label: 'Avisos',
          route: Routes.alerts,
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
          icon: Icons.calendar_today_rounded,
          label: 'Horario',
          route: Routes.schedule,
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

  // Geometría de la barra (coords dentro del SizedBox).
  static const double _barTop = 8; // borde superior de la barra
  static const double _height = 80; // alto total (barTop + cuerpo)
  static const double _circle = 40; // diámetro del círculo activo
  // Negativo => el círculo queda POR DEBAJO de la línea superior (contenido).
  static const double _protrude = -4;
  static const double _notchMargin = 6; // separación círculo↔notch

  // Centro vertical del círculo y elevación desde el centro del cuerpo.
  static const double _circleCenterY = _barTop + _circle / 2 - _protrude;
  static const double _lift =
      _barTop + (_height - _barTop) / 2 - _circleCenterY;

  /// Color único de la barra (para todas las pestañas).
  static const Color _barColor = Color(0xFF4C8DF5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role =
        ref.watch(authControllerProvider).user?.activeRole ?? AppRole.student;
    final tabs = navTabsForRole(role);
    final unread = ref.watch(totalUnreadProvider).asData?.value ?? 0;
    const barColor = _barColor;

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

    // Fondo opaco del color de la página: cubre el contenido del panel en toda
    // la franja del navbar (márgenes y notch incluidos), para que la barra
    // flotante no deje ver las tarjetas por detrás.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SizedBox(
            height: _height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cx = activeIndex >= 0
                    ? (activeIndex + 0.5) * w / tabs.length
                    : null;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Barra pintada con el notch cóncavo alrededor del círculo.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _NavBarPainter(
                          color: barColor,
                          barTop: _barTop,
                          cornerRadius: 16,
                          cx: cx,
                          circleCenterY: _circleCenterY,
                          guestRadius: _circle / 2 + _notchMargin,
                        ),
                      ),
                    ),
                    // Íconos dentro del cuerpo de la barra.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _barTop,
                      bottom: 0,
                      child: Row(
                        children: [
                          for (var i = 0; i < tabs.length; i++)
                            Expanded(
                              child: _NavSlot(
                                icon: tabs[i].icon,
                                active: i == activeIndex,
                                barColor: barColor,
                                lift: _lift,
                                badge:
                                    tabs[i].route == Routes.chat ? unread : 0,
                                onTap: () {
                                  if (i != activeIndex) {
                                    context.go(tabs[i].route);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.icon,
    required this.active,
    required this.barColor,
    required this.lift,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final bool active;
  final Color barColor;
  final double lift;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = active
        ? Transform.translate(
            offset: Offset(0, -lift),
            child: _ActiveCircle(icon: icon, color: barColor),
          )
        : Icon(icon, color: Colors.white, size: 24);

    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (badge > 0)
              Positioned(
                right: active ? -2 : -8,
                top: active ? -18 : -6,
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

/// Círculo blanco elevado del ítem activo, con el ícono en el color de la barra.
class _ActiveCircle extends StatelessWidget {
  const _ActiveCircle({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Pinta la barra con esquinas redondeadas y, si hay ítem activo, un notch
/// cóncavo (curva hacia abajo) que rodea el círculo dejando una separación,
/// de modo que el círculo parece flotar.
class _NavBarPainter extends CustomPainter {
  _NavBarPainter({
    required this.color,
    required this.barTop,
    required this.cornerRadius,
    required this.cx,
    required this.circleCenterY,
    required this.guestRadius,
  });

  final Color color;
  final double barTop;
  final double cornerRadius;
  final double? cx;
  final double circleCenterY;
  final double guestRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final host = Rect.fromLTWH(0, barTop, w, size.height - barTop);
    final rounded = Path()
      ..addRRect(
        RRect.fromRectAndRadius(host, Radius.circular(cornerRadius)),
      );

    Path barPath;
    final c = cx;
    if (c == null) {
      barPath = rounded;
    } else {
      // Círculo (con margen) en la posición del ítem activo: talla el notch.
      final guest = Rect.fromCircle(
        center: Offset(c, circleCenterY),
        radius: guestRadius,
      );
      final notched =
          const CircularNotchedRectangle().getOuterPath(host, guest);
      barPath = Path.combine(PathOperation.intersect, notched, rounded);
    }

    canvas.drawShadow(barPath, Colors.black, 6, false);
    canvas.drawPath(
        barPath,
        Paint()
          ..color = color
          ..isAntiAlias = true,);
  }

  @override
  bool shouldRepaint(_NavBarPainter old) =>
      old.color != color ||
      old.cx != cx ||
      old.barTop != barTop ||
      old.circleCenterY != circleCenterY ||
      old.guestRadius != guestRadius;
}
