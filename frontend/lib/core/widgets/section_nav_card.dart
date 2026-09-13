import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tarjeta de acceso a una sección, estilo "home" vibrante: color sólido con
/// gradiente y patrón decorativo, ícono en círculo blanco a la izquierda,
/// título + subtítulo en blanco y una flecha en círculo a la derecha. Toda la
/// tarjeta es tocable. Se usa para Materias, Tareas y Notas en el dashboard.
class SectionNavCard extends StatelessWidget {
  const SectionNavCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Color base de la tarjeta.
  final Color color;

  /// Dato "de un vistazo" opcional (p. ej. "8 materias", "3 pendientes").
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.14)!;
    final deep = Color.lerp(color, Colors.black, 0.06)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.xl),
      child: Stack(
        children: [
          // Fondo con gradiente suave.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [light, deep],
                ),
              ),
            ),
          ),
          // Patrón decorativo: burbujas translúcidas.
          Positioned(
            right: -34,
            top: -30,
            child: _bubble(190, Colors.white.withValues(alpha: 0.10)),
          ),
          Positioned(
            right: 40,
            bottom: -56,
            child: _bubble(130, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            left: -46,
            bottom: -34,
            child: _bubble(120, Colors.white.withValues(alpha: 0.05)),
          ),
          // Contenido tocable.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Row(
                  children: [
                    // Ícono en círculo blanco.
                    Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(width: 8),
                                _Badge(badge!),
                              ],
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Flecha en círculo claro.
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: color,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bubble(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Chip translúcido para el dato "de un vistazo" sobre la tarjeta de color.
class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Text(
        text,
        style: context.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
