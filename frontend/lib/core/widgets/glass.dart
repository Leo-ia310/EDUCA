import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Superficie de **vidrio esmerilado** (glassmorphism): desenfoca lo que hay
/// detrás y aplica un relleno translúcido + borde tenue. Úsala en overlays y
/// hojas, no sobre fondos opacos (necesita algo detrás para desenfocar).
///
/// En Flutter web el blur cuesta; mantén el [blur] moderado y el área acotada.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 18,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.xl)),
    this.padding,
  });

  final Widget child;
  final double blur;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = (dark ? const Color(0xFF17181B) : Colors.white)
        .withValues(alpha: dark ? 0.60 : 0.68);
    final border = Colors.white.withValues(alpha: dark ? 0.12 : 0.55);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: Border.all(color: border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Hoja inferior con fondo de vidrio esmerilado (frosted). Reemplaza a
/// `showModalBottomSheet` cuando quieras el look premium translúcido.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => GlassSurface(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.palette.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}
