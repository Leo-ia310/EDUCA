import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/providers.dart';
import '../constants/app_strings.dart';
import '../routing/route_paths.dart';
import '../theme/app_theme.dart';

/// Navega entre las 4 pestañas principales (Inicio, Horario, Mensajes, Perfil)
/// usando `context.go`, de modo que se reemplazan en lugar de apilarse: así las
/// cuatro se comportan como una barra de pestañas y ninguna aparece como una
/// "ventana" separada con flecha de retroceso. [homeRoute] es el dashboard del
/// rol activo. Si [item] ya es la pestaña [current], no hace nada; [current]
/// puede ser `null` en pantallas que no son una de las 4 pestañas (p. ej.
/// materias, notas), donde cualquier ítem debe navegar siempre.
void goToEducaTab(
  BuildContext context, {
  required EducaNavItem item,
  required EducaNavItem? current,
  required String homeRoute,
}) {
  if (item == current) return;
  switch (item) {
    case EducaNavItem.home:
      context.go(homeRoute);
    case EducaNavItem.schedule:
      context.go(Routes.schedule);
    case EducaNavItem.messages:
      context.go(Routes.chat);
    case EducaNavItem.profile:
      context.go(Routes.profile);
  }
}

/// Bottom nav con 4 ítems estándar (Inicio, Horario, Mensajes, Perfil).
/// [current] resalta la pestaña activa; `null` no resalta ninguna (útil en
/// pantallas navegables que no son una pestaña, como materias o notas).
///
/// Muestra automáticamente un badge de no leídos sobre "Mensajes"
/// (vía [totalUnreadProvider]), de modo que aparece en todas las pantallas
/// que usan el bottom nav sin pasarlo manualmente.
class EducaBottomNav extends ConsumerWidget {
  const EducaBottomNav({
    super.key,
    required this.current,
    required this.onTap,
  });

  final EducaNavItem? current;
  final ValueChanged<EducaNavItem> onTap;

  // Geometría de la barra (coords dentro del SizedBox).
  static const double _flatTop = 22; // espacio sobre el cuerpo (para el círculo)
  static const double _circle = 40; // diámetro del círculo activo
  static const double _notchMargin = 6; // separación entre círculo y notch

  /// Color de la barra según la pestaña activa (cada tab su color). En
  /// pantallas sin pestaña activa se usa un color neutro.
  static Color _navColor(EducaNavItem? item) => switch (item) {
        EducaNavItem.home => const Color(0xFF4C8DF5),
        EducaNavItem.schedule => const Color(0xFF8A5CF6),
        EducaNavItem.messages => const Color(0xFF33B7A0),
        EducaNavItem.profile => const Color(0xFFF3993E),
        null => const Color(0xFF3B414D),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMessages = ref.watch(totalUnreadProvider).asData?.value ?? 0;
    final barColor = _navColor(current);
    final activeIndex = current?.index;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SizedBox(
          height: _flatTop + 44,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cx = activeIndex != null
                  ? (activeIndex + 0.5) * w / EducaNavItem.values.length
                  : null;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Barra pintada con un bulto alrededor del ítem activo.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _NavBarPainter(
                        color: barColor,
                        flatTop: _flatTop,
                        cornerRadius: 26,
                        notchMargin: _notchMargin,
                        circleRadius: _circle / 2,
                        cx: cx,
                      ),
                    ),
                  ),
                  // Íconos dentro del cuerpo de la barra.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _flatTop,
                    bottom: 0,
                    child: Row(
                      children: [
                        for (final item in EducaNavItem.values)
                          Expanded(
                            child: _NavSlot(
                              item: item,
                              active: item == current,
                              barColor: barColor,
                              badge: item == EducaNavItem.messages
                                  ? unreadMessages
                                  : 0,
                              onTap: () => onTap(item),
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
    );
  }
}

enum EducaNavItem {
  home(Icons.home_rounded, AppStrings.navHome),
  schedule(Icons.calendar_today_rounded, AppStrings.navSchedule),
  messages(Icons.chat_bubble_rounded, AppStrings.navMessages),
  profile(Icons.person_rounded, AppStrings.navProfile);

  const EducaNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.item,
    required this.active,
    required this.barColor,
    required this.onTap,
    this.badge = 0,
  });

  final EducaNavItem item;
  final bool active;
  final Color barColor;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = active
        ? Transform.translate(
            offset: const Offset(0, -22),
            child: _ActiveCircle(icon: item.icon, color: barColor),
          )
        : Icon(item.icon, color: Colors.white, size: 24);

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
                    borderRadius: BorderRadius.circular(10),
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
    required this.flatTop,
    required this.cornerRadius,
    required this.notchMargin,
    required this.circleRadius,
    required this.cx,
  });

  final Color color;
  final double flatTop;
  final double cornerRadius;
  final double notchMargin;
  final double circleRadius;
  final double? cx;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final host = Rect.fromLTWH(0, flatTop, w, size.height - flatTop);
    final rounded = Path()
      ..addRRect(
        RRect.fromRectAndRadius(host, Radius.circular(cornerRadius)),
      );

    Path barPath;
    final c = cx;
    if (c == null) {
      barPath = rounded;
    } else {
      // El círculo (con margen) centrado sobre el borde superior de la barra.
      final guest = Rect.fromCircle(
        center: Offset(c, flatTop),
        radius: circleRadius + notchMargin,
      );
      final notched =
          const CircularNotchedRectangle().getOuterPath(host, guest);
      barPath = Path.combine(PathOperation.intersect, notched, rounded);
    }

    canvas.drawShadow(barPath, Colors.black, 6, false);
    canvas.drawPath(barPath, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_NavBarPainter old) =>
      old.color != color ||
      old.cx != cx ||
      old.flatTop != flatTop ||
      old.notchMargin != notchMargin ||
      old.circleRadius != circleRadius;
}
