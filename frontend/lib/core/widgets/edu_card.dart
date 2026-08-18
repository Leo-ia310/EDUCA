import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tarjeta blanca (o de superficie) con bordes suaves, sombra sutil y padding
/// estándar. Es la primitiva visual de prácticamente todas las pantallas.
class EduCard extends StatelessWidget {
  const EduCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderRadius = 20,
    this.border,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double borderRadius;
  final BoxBorder? border;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = color ?? palette.cardElevated;
    final radius = BorderRadius.circular(borderRadius);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border ??
            Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      ),
    );
  }
}
