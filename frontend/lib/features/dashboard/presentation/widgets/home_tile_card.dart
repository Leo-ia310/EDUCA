import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Tarjeta **horizontal** de acceso rápido del home del estudiante: ícono en
/// círculo blanco a la izquierda, título + subtítulo, y una flecha en círculo
/// a la derecha, sobre un degradado vívido con una burbuja decorativa
/// translúcida. Se apilan una encima de otra (ver `_HomeOptionsList` en el
/// dashboard).
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Color de acento por categoría (define el degradado de la tarjeta).
  final Color color;

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
                // Burbuja decorativa translúcida, sangrando por la esquina.
                Positioned(
                  right: -36,
                  top: -34,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
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
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
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
