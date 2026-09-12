import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';

/// Un tile de métrica: ícono + color + valor (con count-up) + etiqueta.
class StatTile {
  const StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.decimals = 0,
    this.suffix = '',
  });

  final IconData icon;
  final Color color;
  final double value;
  final String label;
  final int decimals;
  final String suffix;
}

/// Franja de métricas "de un vistazo" bajo el saludo. Reutilizable por cualquier
/// rol: cada uno pasa sus [tiles]. Mismo lenguaje que el resto del panel
/// (tarjeta pastel + ícono en círculo vívido, número con count-up).
class DashboardStatStrip extends StatelessWidget {
  const DashboardStatStrip({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _StatTileView(tile: tiles[i])),
        ],
      ],
    );
  }
}

class _StatTileView extends StatelessWidget {
  const _StatTileView({required this.tile});
  final StatTile tile;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(tile.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(tile.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: tile.value),
            duration: context.motion(AppMotion.slow),
            curve: AppMotion.standard,
            builder: (context, v, _) => Text(
              '${v.toStringAsFixed(tile.decimals)}${tile.suffix}',
              style: context.textTheme.titleLarge?.copyWith(
                color: s.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tile.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall?.copyWith(
              color: s.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
