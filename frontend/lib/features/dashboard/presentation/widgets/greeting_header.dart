import 'package:flutter/material.dart';

import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_theme.dart';

/// Hero de bienvenida reutilizable (cualquier rol), full-bleed: banda superior
/// con degradado multicolor, avatar + botones circulares arriba, y debajo la
/// fecha, el saludo grande en dos líneas y un chip de contexto configurable.
/// Da la sensación de "panel", no solo texto.
class AppGreetingHeader extends StatelessWidget {
  const AppGreetingHeader({
    super.key,
    required this.greeting,
    required this.name,
    required this.initials,
    required this.dateLabel,
    this.chipIcon,
    this.chipLabel,
    this.notificationsBadge = 0,
    this.onNotificationsTap,
    this.settingsMenu,
  });

  final String greeting;
  final String name;
  final String initials;
  final String dateLabel;

  /// Chip de contexto opcional (ícono + texto) bajo el nombre. Cada rol pone su
  /// dato (p. ej. "3 tareas para hoy", "2 avisos nuevos").
  final IconData? chipIcon;
  final String? chipLabel;
  final int notificationsBadge;
  final VoidCallback? onNotificationsTap;

  /// Menú de ajustes (p. ej. AccountSettingsMenu circular) a la derecha.
  final Widget? settingsMenu;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: Stack(
        children: [
          // Degradado multicolor vibrante.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.hero),
            ),
          ),
          // Contenido.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials,
                        style: context.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF5B3EA6),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (onNotificationsTap != null)
                      CircleIconButton(
                        icon: Icons.notifications_outlined,
                        onTap: onNotificationsTap!,
                        badge: notificationsBadge,
                      ),
                    if (settingsMenu != null) ...[
                      const SizedBox(width: 10),
                      settingsMenu!,
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  dateLabel,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$greeting,',
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                if (chipLabel != null) ...[
                  const SizedBox(height: 16),
                  // Chip de contexto (configurable por rol).
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (chipIcon != null) ...[
                          Icon(chipIcon, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          chipLabel!,
                          style: context.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// Botón de acción circular para el hero (blanco translúcido), con badge.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.danger,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
