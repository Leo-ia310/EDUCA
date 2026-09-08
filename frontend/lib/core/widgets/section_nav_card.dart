import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'edu_card.dart';

/// Tarjeta de acceso a una sección: ícono a la izquierda, título (y subtítulo
/// opcional) al centro, y una punta de flecha a la derecha. Toda la tarjeta es
/// tocable. Se usa para Materias, Tareas y Notas en el dashboard del alumno.
class SectionNavCard extends StatelessWidget {
  const SectionNavCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Widget a la derecha, antes de la flecha (p. ej. un dato "de un vistazo":
  /// nº de materias, tareas pendientes, promedio).
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: palette.limeDeep, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: palette.limeDeep),
        ],
      ),
    );
  }
}
