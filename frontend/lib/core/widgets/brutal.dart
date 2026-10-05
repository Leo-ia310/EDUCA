import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Estilo "neo-brutalista" del panel de estudiante: borde grueso de tinta,
/// sombra dura desplazada y colores planos.
abstract final class Brutal {
  static const double border = 2;
  static const double shadowOffset = 4;

  /// Color de tinta del borde y la sombra (negro en claro, blanco en oscuro).
  static Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : Colors.black;

  /// Decoración de tarjeta con borde y sombra dura.
  static BoxDecoration decoration(
    BuildContext context, {
    Color? color,
    Gradient? gradient,
    double radius = Radii.md,
    double offset = shadowOffset,
    bool shadow = true,
  }) {
    final i = ink(context);
    return BoxDecoration(
      color: gradient == null ? (color ?? context.palette.cardElevated) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: i, width: border),
      boxShadow: shadow
          ? [BoxShadow(color: i, offset: Offset(offset, offset))]
          : null,
    );
  }
}

/// Contenedor con el estilo [Brutal]. Reserva a la derecha/abajo el espacio de
/// la sombra para que no se recorte dentro de listas y grids.
class BrutalBox extends StatefulWidget {
  const BrutalBox({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.gradient,
    this.radius = Radii.md,
    this.padding,
    this.offset = Brutal.shadowOffset,
    this.clip = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double offset;

  /// Recorta el contenido a la forma de la tarjeta (íconos de fondo, etc.).
  final bool clip;

  @override
  State<BrutalBox> createState() => _BrutalBoxState();
}

class _BrutalBoxState extends State<BrutalBox> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.offset;
    // Al presionar, la tarjeta "se hunde" hacia su sombra.
    final shift = _down ? o * 0.6 : 0.0;
    Widget content = widget.padding != null
        ? Padding(padding: widget.padding!, child: widget.child)
        : widget.child;
    if (widget.clip) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius - Brutal.border),
        child: content,
      );
    }
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      transform: Matrix4.translationValues(shift, shift, 0),
      decoration: Brutal.decoration(
        context,
        color: widget.color,
        gradient: widget.gradient,
        radius: widget.radius,
        offset: o - shift,
      ),
      child: content,
    );
    return Padding(
      padding: EdgeInsets.only(right: o, bottom: o),
      child: widget.onTap == null
          ? box
          : GestureDetector(
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _down = true),
              onTapUp: (_) => setState(() => _down = false),
              onTapCancel: () => setState(() => _down = false),
              behavior: HitTestBehavior.opaque,
              child: box,
            ),
    );
  }
}
