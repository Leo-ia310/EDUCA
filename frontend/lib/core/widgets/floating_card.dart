import 'package:flutter/material.dart';
import 'package:flutter_tilt/flutter_tilt.dart';

import '../theme/motion.dart';

/// Envuelve un elemento destacado (héroe) con un efecto 3D sutil: al pasar el
/// cursor o arrastrar, la tarjeta se inclina en perspectiva y "flota".
///
/// Calibrado para no distraer: ángulo bajo, sin brillo, y **sin sensores**
/// (nada de giroscopio que se mueva solo). Se desactiva por completo si el
/// usuario pidió reducir movimiento. Parte de "Sereno en movimiento".
class FloatingCard extends StatelessWidget {
  const FloatingCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.angle = 6,
  });

  final Widget child;
  final double borderRadius;

  /// Ángulo máximo de inclinación, en grados.
  final double angle;

  @override
  Widget build(BuildContext context) {
    // Aísla los repintados continuos del tilt del resto de la pantalla.
    return RepaintBoundary(
      child: Tilt.base(
        disable: context.reduceMotion,
        borderRadius: BorderRadius.circular(borderRadius),
        tiltConfig: TiltConfig(
          angle: angle,
          enableGestureSensors: false,
          enableReverse: false,
          moveDuration: AppMotion.fast,
          leaveDuration: AppMotion.slow,
        ),
        lightConfig: const LightConfig(disable: true),
        shadowConfig: const ShadowBaseConfig(disable: true),
        child: child,
      ),
    );
  }
}
