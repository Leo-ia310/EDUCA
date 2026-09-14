import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';

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

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.cardElevated,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
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
  }
}
