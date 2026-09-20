import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/motion.dart';

/// Entrada escalonada (fade + leve desplazamiento) para ítems de una lista.
/// Respeta "reducir movimiento": devuelve el hijo tal cual.
Widget entranceItem(BuildContext context, int index, Widget child) {
  if (context.reduceMotion) return child;
  final delay = Duration(milliseconds: (index * 40).clamp(0, 400));
  return child
      .animate()
      .fadeIn(duration: AppMotion.base, delay: delay, curve: AppMotion.standard)
      .moveY(
        begin: 10,
        end: 0,
        duration: AppMotion.base,
        delay: delay,
        curve: AppMotion.standard,
      );
}

/// Crossfade entre estados de una zona (p. ej. esqueleto → contenido).
/// Envuelve el resultado de un `asyncValue.when(...)`.
Widget crossfadeState(BuildContext context, Widget child) {
  return AnimatedSwitcher(
    duration: context.motion(AppMotion.base),
    switchInCurve: AppMotion.standard,
    switchOutCurve: AppMotion.standard,
    child: child,
  );
}
