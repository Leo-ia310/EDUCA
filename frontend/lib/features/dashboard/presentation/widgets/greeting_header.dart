import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/floating_card.dart';

/// Encabezado con la marca "Educa360" + acciones. Aparece en los 4
/// dashboards.
class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    this.onSettingsTap,
    this.onNotificationsTap,
    this.onChatTap,
    this.notificationsBadge = 0,
    this.chatBadge = 0,
  });

  final VoidCallback? onSettingsTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onChatTap;
  final int notificationsBadge;
  final int chatBadge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.palette.limeDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Color(0xFF1E2218),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Educa360',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (onChatTap != null) ...[
            _TopIcon(
              icon: Icons.chat_bubble_outline,
              onTap: onChatTap!,
              badge: chatBadge,
            ),
            const SizedBox(width: 8),
          ],
          if (onNotificationsTap != null)
            _TopIcon(
              icon: Icons.notifications_outlined,
              onTap: onNotificationsTap!,
              badge: notificationsBadge,
            ),
          if (onSettingsTap != null) ...[
            const SizedBox(width: 8),
            _TopIcon(icon: Icons.settings_outlined, onTap: onSettingsTap!),
          ],
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: context.palette.cardElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.danger,
                borderRadius: BorderRadius.circular(10),
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

class GreetingBanner extends StatelessWidget {
  const GreetingBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.institutionName,
    this.slogan,
    this.crest,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  /// Nombre del colegio, mostrado como etiqueta sobre el saludo.
  final String? institutionName;

  /// Eslogan del colegio, mostrado como cita bajo el subtítulo.
  final String? slogan;

  /// Escudo/emblema del colegio, a la izquierda del saludo.
  final Widget? crest;

  // Tonos oscuros legibles sobre el fondo salvia.
  static const Color _ink = Color(0xFF1E2218);
  static const Color _inkSoft = Color(0xFF34401C);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (institutionName != null) ...[
          Text(
            institutionName!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall?.copyWith(
              color: _inkSoft,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          title,
          style: context.textTheme.headlineSmall?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: context.textTheme.bodyMedium?.copyWith(
            color: _inkSoft,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (slogan != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B5A11),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  slogan!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: _inkSoft,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    final body = crest == null
        ? info
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              crest!,
              const SizedBox(width: 16),
              Expanded(child: info),
            ],
          );

    return FloatingCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.lime,
              Color.lerp(palette.lime, palette.limeSoft, 0.35)!,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            if (trailing != null) ...[
              const SizedBox(height: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
