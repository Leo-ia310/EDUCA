import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../profile/presentation/widgets/account_settings_menu.dart';

/// Barra superior del home del estudiante (reemplaza al hero de bienvenida con
/// foto). Banda **full-bleed** con fondo azul —el mismo del navbar— que cubre
/// todo el ancho y el borde superior. El borde inferior es recto: el panel se
/// monta encima con esquinas redondeadas (curva cóncava), así el radio parece
/// del panel y no de la barra. A la izquierda el avatar de perfil + el nombre;
/// a la derecha las acciones (notificaciones + configuración).
class StudentHomeHeader extends StatelessWidget {
  const StudentHomeHeader({
    super.key,
    required this.name,
    required this.initials,
    required this.onNotificationsTap,
    this.avatarUrl,
    this.notificationsBadge = 0,
  });

  final String name;
  final String initials;
  final VoidCallback onNotificationsTap;
  final String? avatarUrl;
  final int notificationsBadge;

  @override
  Widget build(BuildContext context) {
    const barColor = EducaBottomNav.barColor;
    // Inset superior (status bar / notch): lo absorbe la banda para llegar
    // hasta el borde de la pantalla.
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      // Borde inferior recto y con holgura extra abajo: el panel se monta
      // encima (solape = radio) y aporta la curva sin tapar el contenido.
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 12, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [barColor, Color(0xFF3B74D6)],
        ),
      ),
      child: Row(
        children: [
          _Avatar(initials: initials, avatarUrl: avatarUrl, barColor: barColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CircleAction(
            icon: Icons.notifications_rounded,
            tooltip: 'Notificaciones',
            badge: notificationsBadge,
            onTap: onNotificationsTap,
          ),
          const SizedBox(width: 10),
          const AccountSettingsMenu(circular: true),
        ],
      ),
    );
  }
}

/// Botón de acción circular blanco translúcido (para el fondo azul), con badge.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;
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
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Avatar circular de perfil: foto de red si hay [avatarUrl]; si no, las
/// iniciales en el azul de la barra sobre un círculo blanco.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.barColor,
    this.avatarUrl,
  });

  final String initials;
  final Color barColor;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      initials,
      style: context.textTheme.titleMedium?.copyWith(
        color: barColor,
        fontWeight: FontWeight.w800,
      ),
    );
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: (avatarUrl != null &&
              avatarUrl!.isNotEmpty &&
              avatarUrl!.startsWith('http'))
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : label,
                errorBuilder: (_, __, ___) => label,
              ),
            )
          : label,
    );
  }
}
