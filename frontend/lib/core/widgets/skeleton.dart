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

/// Placeholder de una fila-tarjeta: círculo (avatar/ícono) + dos líneas, para
/// imitar la forma real del contenido mientras carga.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, this.height = 72});

  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.cardElevated,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, 12),
                const SizedBox(height: 8),
                bar(120, 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de carga por defecto para dashboards y listas: N tarjetas-esqueleto
/// (círculo + líneas) con el brillo de shimmer. Reemplaza al spinner para una
/// carga más ordenada y acorde al contenido real.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.items = 4,
    this.itemHeight = 72,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  final int items;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // ClampingScrollPhysics deshabilitado: solo evita el overflow cuando el
    // esqueleto se coloca dentro de un alto acotado (p. ej. un Expanded).
    return SingleChildScrollView(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < items - 1 ? 12 : 0),
                child: SkeletonTile(height: itemHeight),
              ),
          ],
        ),
      ),
    );
  }
}
