import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/floating_card.dart';

/// Tarjeta **cuadrada** de acceso rápido del home del estudiante. Superficie
/// blanca (elevada) con sombra para resaltar del fondo; ícono grande sin fondo
/// circular arriba-centro, y el título centrado debajo.
///
/// Si [onTap] es null la tarjeta se muestra igual pero no navega (sección aún
/// sin conectar); se atenúa levemente para diferenciarla de las activas.
class HomeTileCard extends StatelessWidget {
  const HomeTileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;

  /// Color de acento del ícono (por categoría).
  final Color color;

  /// Acción al tocar. Si es null, la tarjeta es inerte.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    final palette = context.palette;
    final enabled = onTap != null;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: s.vivid, size: 38),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    // Superficie con un leve resplandor del color de la categoría arriba, para
    // dar vida sin abandonar la tarjeta neutra.
    final top = Color.alphaBlend(
      s.vivid.withValues(alpha: 0.12),
      palette.cardElevated,
    );

    final card = Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, palette.cardElevated],
          ),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: s.vivid.withValues(alpha: 0.28),
          ),
          boxShadow: AppShadows.lifted(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: content,
          ),
        ),
      ),
    );

    // Tilt 3D en perspectiva (se desactiva con "reducir movimiento").
    return FloatingCard(borderRadius: Radii.lg, angle: 9, child: card);
  }
}
