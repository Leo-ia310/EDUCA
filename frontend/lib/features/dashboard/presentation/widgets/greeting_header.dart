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
    this.avatarUrl,
    this.heroImageUrl,
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

  /// Foto del usuario para el avatar circular. Si es null o falla la carga, se
  /// muestran las iniciales.
  final String? avatarUrl;

  /// Foto grande integrada al fondo del hero (a la derecha, desvanecida hacia el
  /// degradado), estilo "tarjeta de perfil". Si se pasa, se oculta el avatar
  /// circular. Solo el panel del alumno la usa por ahora.
  final String? heroImageUrl;

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
          // Foto grande del alumno, anclada a la derecha. Un recorte sin fondo
          // (asset) se integra directo; una foto de red se desvanece por el
          // borde izquierdo para fundirse en el degradado.
          if (heroImageUrl != null && heroImageUrl!.isNotEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: _buildHeroPhoto(heroImageUrl!),
                ),
              ),
            ),
          // Contenido. Con foto grande el hero crece un poco para dar aire a la
          // figura (cabeza + torso).
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              (heroImageUrl != null && heroImageUrl!.isNotEmpty) ? 56 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (heroImageUrl == null || heroImageUrl!.isEmpty)
                      Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                          ? ClipOval(
                              child: Image.network(
                                avatarUrl!,
                                width: 54,
                                height: 54,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                        ? child
                                        : _initialsLabel(context),
                                errorBuilder: (_, __, ___) =>
                                    _initialsLabel(context),
                              ),
                            )
                          : _initialsLabel(context),
                    ),
                    const Spacer(),
                    if (onNotificationsTap != null)
                      CircleIconButton(
                        icon: Icons.notifications_rounded,
                        onTap: onNotificationsTap!,
                        badge: notificationsBadge,
                        tooltip: 'Notificaciones',
                      ),
                    if (settingsMenu != null) ...[
                      const SizedBox(width: 10),
                      settingsMenu!,
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                FractionallySizedBox(
                  widthFactor:
                      (heroImageUrl != null && heroImageUrl!.isNotEmpty)
                          ? 0.64
                          : 1.0,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        Flexible(
                          child: Text(
                            chipLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
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
          ),
        ],
      ),
    );
  }

  Widget _initialsLabel(BuildContext context) => Text(
        initials,
        style: context.textTheme.titleLarge?.copyWith(
          color: const Color(0xFF5B3EA6),
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _buildHeroPhoto(String src) {
    final isNetwork = src.startsWith('http');
    final Widget image = isNetwork
        ? Image.network(
            src,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          )
        : Image.asset(
            src,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    // Recorte transparente (asset): sin desvanecido, se integra tal cual.
    if (!isNetwork) return image;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.transparent, Colors.white, Colors.white],
        stops: [0.0, 0.4, 1.0],
      ).createShader(rect),
      child: image,
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
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  /// Etiqueta accesible + hint al pasar el cursor (el botón es solo ícono).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: Tooltip(
            message: tooltip ?? '',
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
