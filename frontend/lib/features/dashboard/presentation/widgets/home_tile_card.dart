import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';

/// Tarjeta **horizontal** de acceso rápido del home del estudiante: ícono en
/// círculo blanco a la izquierda, título + subtítulo, una ilustración
/// temática decorativa y una flecha (sin círculo) a la derecha, sobre un
/// degradado vívido. Se apilan una encima de otra (ver `_HomeOptionsList` en
/// el dashboard).
///
/// Si [onTap] es null la tarjeta se muestra igual pero no navega (sección aún
/// sin conectar); se atenúa levemente para diferenciarla de las activas.
class HomeOptionCard extends StatelessWidget {
  const HomeOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.art,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Color de acento por categoría (define el degradado de la tarjeta).
  final Color color;

  /// Ilustración decorativa temática (ver [ArtCluster]), entre el texto y la
  /// flecha.
  final Widget? art;

  /// Acción al tocar. Si es null, la tarjeta es inerte.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = Brutal.ink(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // En oscuro la tarjeta se tiñe con su color de categoría (20 %) sobre la
    // superficie y la tinta es clara; en claro, texto negro o blanco según la
    // luminosidad del color.
    final cardColor = dark ? AppColors.darkSurface : color;
    final fg = dark
        ? AppColors.textDark
        : (color.computeLuminance() > 0.3 ? Colors.black : Colors.white);
    final artColor = dark ? color.withValues(alpha: 0.32) : Colors.white;
    final paper = context.paper;
    final onPaper = context.onPaper;
    final iconColor = dark ? color : Colors.black;
    final goColor = dark ? AppColors.accentDark : Colors.white;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: BrutalBox(
        onTap: onTap,
        color: cardColor,
        radius: Radii.lg,
        clip: true,
        child: LayoutBuilder(
          builder: (context, c) {
            // La ilustración ocupa la mitad derecha de la tarjeta, con margen
            // para no tocar los bordes.
            final half = c.maxWidth * 0.52;
            // Con tipografía grande del sistema (celulares reales) el texto puede
            // ocupar más de lo previsto: la tarjeta crece en vez de solaparse.
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Ilustración temática a la derecha (centrada en vertical).
                  if (art != null)
                    Positioned(
                      right: 10,
                      top: 10,
                      bottom: 10,
                      width: half - 10,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 112,
                          height: 108,
                          child: IconTheme(
                            data: IconThemeData(color: artColor),
                            child: art!,
                          ),
                        ),
                      ),
                    ),
                  // Ícono arriba y título + descripción abajo, en un bloque con
                  // altura mínima (define el alto de la tarjeta).
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 196,
                      minWidth: double.infinity,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, half + 4, 18),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: paper,
                              borderRadius: BorderRadius.circular(Radii.md),
                              border:
                                  Border.all(color: ink, width: Brutal.border),
                            ),
                            child: Icon(icon, color: iconColor, size: 28),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: paper,
                                    borderRadius:
                                        BorderRadius.circular(Radii.pill),
                                    border: Border.all(
                                      color: ink,
                                      width: Brutal.border,
                                    ),
                                  ),
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        context.textTheme.labelMedium?.copyWith(
                                      color: onPaper,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        context.textTheme.titleLarge?.copyWith(
                                      color: fg,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Flecha negra en círculo blanco, esquina inferior derecha.
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: goColor,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: ink, width: Brutal.border),
                      ),
                      child: _BoldArrow(
                        color: dark ? AppColors.onAccentDark : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Flecha "→" con trazo reforzado (varias copias superpuestas con un leve
/// desplazamiento, ya que `Icon` no admite grosor de trazo).
class _BoldArrow extends StatelessWidget {
  const _BoldArrow({this.color = Colors.black});

  final Color color;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    Widget arrow(Offset offset) => Transform.translate(
          offset: offset,
          child: Icon(
            Icons.arrow_forward_rounded,
            size: _size,
            color: color,
          ),
        );
    return SizedBox(
      width: _size + 2,
      height: _size + 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          arrow(const Offset(-0.7, 0)),
          arrow(const Offset(0.7, 0)),
          arrow(const Offset(0, -0.7)),
          arrow(const Offset(0, 0.7)),
          arrow(Offset.zero),
        ],
      ),
    );
  }
}

/// Un elemento decorativo (ícono o texto corto) dentro de un [ArtCluster].
class ArtItem {
  const ArtItem.icon(
    IconData this.icon, {
    required this.size,
    this.top = 0,
    this.right = 0,
    this.angle = 0,
    this.opacity = 0.4,
  }) : text = null;

  const ArtItem.text(
    String this.text, {
    required this.size,
    this.top = 0,
    this.right = 0,
    this.angle = 0,
    this.opacity = 0.4,
  }) : icon = null;

  final IconData? icon;
  final String? text;
  final double size;
  final double top;
  final double right;
  final double angle;
  final double opacity;
}

/// Cúmulo de íconos/texto decorativos que ilustran el tema de la tarjeta
/// (p. ej. lápices para "Tareas"), colocado entre el texto y la flecha.
class ArtCluster extends StatelessWidget {
  const ArtCluster(this.items, {super.key});
  final List<ArtItem> items;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final it in items)
          Positioned(
            top: it.top,
            right: it.right,
            child: Transform.rotate(
              angle: it.angle,
              child: it.icon != null
                  ? Icon(
                      it.icon,
                      size: it.size,
                      color: (IconTheme.of(context).color ?? Colors.white)
                          .withValues(alpha: dark ? 1 : it.opacity),
                    )
                  : Opacity(
                      opacity: it.opacity,
                      child: Text(
                        it.text!,
                        style: TextStyle(
                          fontSize: it.size,
                          fontWeight: FontWeight.w900,
                          color: IconTheme.of(context).color ?? Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
