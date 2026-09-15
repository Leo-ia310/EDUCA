import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'floating_card.dart';

/// Tarjeta con **profundidad** del sistema Educa v3: superficie elevada con
/// doble sombra (ambiente + contacto), borde/glow opcional del color de acento
/// y, si se pide, **tilt 3D** en perspectiva al pasar el cursor / arrastrar.
///
/// Unifica el "relieve" de todas las tarjetas del producto. Usa [tilt] solo en
/// tarjetas prominentes (no en filas de lista, para no saturar de movimiento).
class DepthCard extends StatelessWidget {
  const DepthCard({
    super.key,
    required this.child,
    this.onTap,
    this.tilt = false,
    this.accent,
    this.glow = false,
    this.soft = false,
    this.borderRadius = Radii.lg,
    this.padding,
    this.color,
    this.gradient,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Activa el tilt 3D en perspectiva. Reservar para tarjetas destacadas.
  final bool tilt;

  /// Color de acento para el borde y el glow superior.
  final Color? accent;

  /// Dibuja un leve resplandor del [accent] en la parte superior.
  final bool glow;

  /// Usa la sombra suave (filas/superficies secundarias) en vez de la elevada.
  final bool soft;

  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Color base de la superficie (por defecto `cardElevated`).
  final Color? color;

  /// Degradado propio (tiene prioridad sobre color/glow).
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = color ?? palette.cardElevated;
    final useGlow = glow && accent != null && gradient == null;

    final decoration = BoxDecoration(
      color: gradient == null && !useGlow ? base : null,
      gradient: gradient ??
          (useGlow
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(accent!.withValues(alpha: 0.12), base),
                    base,
                  ],
                )
              : null),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: accent != null
            ? accent!.withValues(alpha: 0.28)
            : Theme.of(context).dividerColor,
      ),
      boxShadow: soft ? AppShadows.soft(context) : AppShadows.lifted(context),
    );

    Widget inner = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );

    Widget card = DecoratedBox(decoration: decoration, child: inner);

    if (tilt) {
      card = FloatingCard(borderRadius: borderRadius, angle: 9, child: card);
    }
    return card;
  }
}
