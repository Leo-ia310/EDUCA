import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

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
    final light = Color.lerp(color, Colors.white, 0.16)!;
    final deep = Color.lerp(color, Colors.black, 0.22)!;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [light, color, deep],
          ),
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Ilustración temática, grande y pegada al borde derecho;
                // puede quedar parcialmente detrás de la flecha.
                if (art != null)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: -8,
                    width: 132,
                    child: art!,
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    context.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const _BoldArrow(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flecha "→" con trazo reforzado (varias copias superpuestas con un leve
/// desplazamiento, ya que `Icon` no admite grosor de trazo).
class _BoldArrow extends StatelessWidget {
  const _BoldArrow();

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    Widget arrow(Offset offset) => Transform.translate(
          offset: offset,
          child: const Icon(Icons.arrow_forward_rounded,
              size: _size, color: Colors.white,),
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
                      color: Colors.white.withValues(alpha: it.opacity),
                    )
                  : Opacity(
                      opacity: it.opacity,
                      child: Text(
                        it.text!,
                        style: TextStyle(
                          fontSize: it.size,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
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
