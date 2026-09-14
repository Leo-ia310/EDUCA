import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';

/// Tarjeta **cuadrada** de acceso rápido del home del estudiante. Fondo pastel
/// sensible al tema (`context.pastel`), ícono en círculo, un dato "de un
/// vistazo" y el título de la sección.
///
/// Si [onTap] es null la tarjeta se muestra igual pero no navega (sección aún
/// sin conectar); se atenúa levemente para diferenciarla de las activas.
class HomeTileCard extends StatelessWidget {
  const HomeTileCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;

  /// Dato corto que se muestra grande (p. ej. "8.5", "96%", "3 pend.").
  final String? value;

  /// Acción al tocar. Si es null, la tarjeta es inerte.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    final enabled = onTap != null;

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
          const Spacer(),
          if (value != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value!,
                maxLines: 1,
                style: context.textTheme.titleMedium?.copyWith(
                  color: s.ink,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
            ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: s.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: s.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
