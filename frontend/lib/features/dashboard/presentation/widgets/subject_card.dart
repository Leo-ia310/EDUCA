import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/dashboard_models.dart';

/// Tarjeta de materia estilo "quick access": fondo pastel claro, ícono en
/// círculo de color vívido, nombre de la materia, maestro y un chevron. Deriva
/// una versión vívida (círculo) y otra muy clara (fondo) del color de la
/// materia con HSL, para que cada asignatura tenga su hue propio.
class SubjectProgressCard extends StatelessWidget {
  const SubjectProgressCard({super.key, required this.subject, this.onTap});
  final SubjectProgress subject;
  final VoidCallback? onTap;

  static const _ink = Color(0xFF232A33);

  @override
  Widget build(BuildContext context) {
    final base = subject.color ?? subjectColor(subject.name);
    final hsl = HSLColor.fromColor(base);
    final vivid = hsl
        .withSaturation(hsl.saturation.clamp(0.5, 1.0))
        .withLightness(0.56)
        .toColor();
    final cardBg = hsl
        .withSaturation(hsl.saturation.clamp(0.35, 1.0))
        .withLightness(0.94)
        .toColor();
    final inkMuted = _ink.withValues(alpha: 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            height: 138,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícono en círculo de color vívido.
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: vivid,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      subject.icon ?? Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subject.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const Spacer(),
                  // Maestro + chevron al pie.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subject.teacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: inkMuted,
                        size: 20,
                      ),
                    ],
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
