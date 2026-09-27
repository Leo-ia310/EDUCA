import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Tarjeta **horizontal** de acceso rápido del home del estudiante: degradado
/// vívido por categoría, título en blanco alineado a la izquierda, y un
/// ícono grande "marca de agua" que sangra por la esquina inferior derecha,
/// con un par de destellos decorativos. Se apilan una encima de otra (ver
/// `_HomeOptionsList` en el dashboard).
///
/// Si [onTap] es null la tarjeta se muestra igual pero no navega (sección aún
/// sin conectar); se atenúa levemente para diferenciarla de las activas.
class HomeOptionCard extends StatelessWidget {
  const HomeOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;

  /// Color de acento por categoría (define el degradado de la tarjeta).
  final Color color;

  /// Acción al tocar. Si es null, la tarjeta es inerte.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final light = Color.lerp(color, Colors.white, 0.24)!;
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
            child: SizedBox(
              height: 94,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Ícono grande de fondo, sangrando por la esquina.
                  Positioned(
                    right: -16,
                    bottom: -16,
                    child: Transform.rotate(
                      angle: -math.pi / 14,
                      child: Icon(
                        icon,
                        size: 92,
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                  ),
                  // Destellos decorativos.
                  const Positioned(
                    right: 78,
                    top: 20,
                    child: _Sparkle(size: 12),
                  ),
                  const Positioned(
                    right: 58,
                    top: 42,
                    child: _Sparkle(size: 7),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: context.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Destello decorativo (estrella de 4 puntas) sobre el degradado.
class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.auto_awesome_rounded,
      size: size,
      color: Colors.white.withValues(alpha: 0.55),
    );
  }
}
