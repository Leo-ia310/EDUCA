import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// Estado vacío con personalidad: un emblema en capas (halo suave + disco +
/// ícono) sobre el color de acento, título claro, subtítulo legible y una
/// acción opcional. Entra con un fade+scale sereno (respeta "reducir
/// movimiento"). Se usa en toda la app, así que cualquier mejora aquí eleva
/// todas las pantallas.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    this.title = 'Nada por aquí',
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Color del emblema. Por defecto el acento del tema.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = accent ?? palette.accentDeep;

    final emblem = SizedBox(
      width: 108,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo exterior tenue.
          Container(
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
          // Disco medio.
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
          ),
          Icon(icon, size: 36, color: c),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle!,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: palette.textMuted, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(actionLabel!),
          ),
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: context.reduceMotion
            ? content
            : content
                .animate()
                .fadeIn(duration: AppMotion.base, curve: AppMotion.standard)
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1, 1),
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                ),
      ),
    );
  }
}
