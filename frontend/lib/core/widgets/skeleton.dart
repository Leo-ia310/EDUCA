import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// Bloque base de esqueleto: un rectángulo redondeado del color de superficie
/// alterna, para componer placeholders de carga.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Envuelve un árbol de [Skeleton]s con el brillo suave de shimmer. Si el
/// usuario pidió menos movimiento, se muestra estático (sin animación).
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    final palette = context.palette;
    return Shimmer.fromColors(
      baseColor: palette.surfaceAlt,
      highlightColor: Color.lerp(palette.surfaceAlt, palette.cardElevated, 0.6)!,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// Estado de carga por defecto para dashboards y listas: N tarjetas-esqueleto
/// con el brillo de shimmer. Reemplaza al spinner para una carga más ordenada.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.items = 4,
    this.itemHeight = 76,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  final int items;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < items - 1 ? 12 : 0),
                child: Container(
                  height: itemHeight,
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
