import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Cifra que "sube" animada desde 0 hasta [value] al aparecer (dato vivo).
/// Respeta "reducir movimiento": si está activo, muestra el valor final directo.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.decimals = 0,
    this.suffix = '',
    this.prefix = '',
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final int decimals;
  final String suffix;
  final String prefix;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? value : 0, end: value),
      duration: reduce ? Duration.zero : duration,
      curve: AppMotion.standard,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        style: style,
      ),
    );
  }
}
