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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMessages = ref.watch(totalUnreadProvider).asData?.value ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final item in EducaNavItem.values)
                _NavButton(
                  item: item,
                  active: item == current,
                  badge: item == EducaNavItem.messages ? unreadMessages : 0,
                  onTap: () => onTap(item),
                ),
            ],
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  final EducaNavItem item;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activeColor = palette.limeDeep;
    final inactiveColor = palette.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        // FittedBox + mainAxisSize.min: el ítem se reduce si por un frame de
        // transición recibe una altura diminuta, en vez de desbordar.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    item.icon,
                    color: active ? activeColor : inactiveColor,
                    size: 24,
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 1.5,
                          ),
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
              const SizedBox(height: 2),
              Text(
                item.label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: active ? activeColor : inactiveColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 3,
                width: active ? 20 : 0,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
