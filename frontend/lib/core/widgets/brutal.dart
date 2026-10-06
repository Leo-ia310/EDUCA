import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../shared/models/app_role.dart';

import '../theme/app_theme.dart';

/// Estilo "neo-brutalista" del panel de estudiante: borde grueso de tinta,
/// sombra dura desplazada y colores planos.
abstract final class Brutal {
  /// El estilo aplica a los paneles de estudiante, docente y padre.
  static bool active(BuildContext context) {
    final role = ProviderScope.containerOf(context, listen: false)
        .read(authControllerProvider)
        .user
        ?.activeRole;
    return role == AppRole.student ||
        role == AppRole.teacher ||
        role == AppRole.parent;
  }

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

/// Botón con el estilo [Brutal]: relleno plano, borde grueso y sombra dura.
class BrutalButton extends StatelessWidget {
  const BrutalButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
    this.foreground,
    this.expand = false,
    this.height = 44,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  /// Relleno (por defecto el acento de marca).
  final Color? color;
  final Color? foreground;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Colors.white;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
    return BrutalBox(
      onTap: onTap,
      color: color ?? context.palette.accentDeep,
      radius: Radii.md,
      offset: 3,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Píldora/chip seleccionable con el estilo [Brutal].
class BrutalPill extends StatelessWidget {
  const BrutalPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Versión más pequeña (barras de filtros).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg =
        selected ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 3, bottom: 3),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 4 : 8,
        ),
        decoration: Brutal.decoration(
          context,
          color: selected ? palette.accentDeep : palette.cardElevated,
          radius: compact ? Radii.sm : Radii.md,
          offset: compact ? 2 : 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 14 : 16, color: fg),
              SizedBox(width: compact ? 4 : 6),
            ],
            Text(
              label,
              style: (compact
                      ? context.textTheme.labelSmall
                      : context.textTheme.labelMedium)
                  ?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
