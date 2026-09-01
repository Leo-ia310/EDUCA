import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tarjeta blanca (o de superficie) con bordes suaves, sombra sutil y padding
/// estándar. Es la primitiva visual de prácticamente todas las pantallas.
///
/// Si es interactiva (`onTap != null`) responde con un feedback táctil sutil
/// —una leve escala al presionar— parte del pulido "Sereno".
class EduCard extends StatefulWidget {
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
  State<EduCard> createState() => _EduCardState();
}

class _EduCardState extends State<EduCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = widget.color ?? palette.cardElevated;
    final radius = BorderRadius.circular(widget.borderRadius);

    // Sombra: elevada por defecto, o elevada al pasar el cursor (lift en web).
    final lift = _hovered && widget.onTap != null;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: widget.border ??
            Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
        boxShadow: (widget.elevated || lift)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: lift ? 0.08 : 0.04),
                  blurRadius: lift ? 24 : 18,
                  offset: Offset(0, lift ? 9 : 6),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) {
          if (v != _pressed) setState(() => _pressed = v);
        },
        onHover: (v) {
          if (v != _hovered) setState(() => _hovered = v);
        },
        borderRadius: radius,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.98 : 1,
          duration: Duration(milliseconds: reduceMotion ? 0 : 120),
          curve: Curves.easeOut,
          child: card,
        ),
      ),
    );
  }
}
