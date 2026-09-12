import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'edu_card.dart';

/// Tarjeta de indicador canónica de la app: pastilla de ícono en acento pastel,
/// cifra grande, etiqueta y (opcional) un delta de tendencia.
///
/// Reemplaza las variantes ad-hoc que vivían en cada dashboard
/// (`_AdminStatCard`, `_StatCard`, …). Úsala dentro de un `Row`+`Expanded` o un
/// grid para componer filas de indicadores.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accent,
    this.delta,
    this.deltaPositive = true,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final String value;
  final String label;
  final IconData? icon;

  /// Color de acento (pastilla de ícono y delta). Por defecto el salvia hondo.
  final Color? accent;

  /// Texto opcional de tendencia (p. ej. "+2", "-1.4"). Se pinta como chip.
  final String? delta;
  final bool deltaPositive;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accentColor = accent ?? palette.limeDeep;
    final deltaColor = deltaPositive ? palette.success : palette.danger;

    return EduCard(
      padding: padding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: _AnimatedValue(
                  value: value,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delta!,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: deltaColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Muestra una cifra que "cuenta" desde cero al aparecer, conservando el
/// prefijo/sufijo (p. ej. `$`, `%`) y los decimales del texto original. Si el
/// valor no contiene un número, o hay reduce-motion, se muestra directo.
class _AnimatedValue extends StatelessWidget {
  const _AnimatedValue({required this.value, this.style});
  final String value;
  final TextStyle? style;

  static final _re = RegExp(r'^([^0-9-]*)(-?[0-9]+(?:[.,][0-9]+)?)(.*)$');

  @override
  Widget build(BuildContext context) {
    Widget plain() => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    final m = _re.firstMatch(value);
    if (m == null) return plain();
    final prefix = m.group(1)!;
    final numStr = m.group(2)!;
    final suffix = m.group(3)!;
    final target = double.tryParse(numStr.replaceAll(',', '.'));
    if (target == null) return plain();
    final decimals =
        numStr.contains(RegExp(r'[.,]')) ? numStr.split(RegExp(r'[.,]')).last.length : 0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: context.motion(AppMotion.slow),
      curve: AppMotion.standard,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
