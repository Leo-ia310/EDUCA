import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Envuelve una tarjeta con el "container transform": al tocarla, la tarjeta
/// crece hacia la pantalla destino con continuidad espacial, en vez de un
/// cambio de pantalla brusco. Config estándar de "Sereno en movimiento".
///
/// - [closed]: construye la tarjeta cerrada; recibe un callback `open` que debe
///   dispararse al tocarla (p. ej. como `onTap`).
/// - [open]: construye la pantalla destino.
class OpenCard extends StatelessWidget {
  const OpenCard({
    super.key,
    required this.closed,
    required this.open,
    this.borderRadius = 20,
  });

  final Widget Function(BuildContext context, VoidCallback open) closed;
  final WidgetBuilder open;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final ground = Theme.of(context).scaffoldBackgroundColor;
    return OpenContainer(
      tappable: false,
      closedElevation: 0,
      closedColor: Colors.transparent,
      openColor: ground,
      middleColor: ground,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration:
          context.reduceMotion ? AppMotion.fast : AppMotion.slow,
      closedBuilder: (context, openFn) => closed(context, openFn),
      openBuilder: (context, _) => open(context),
    );
  }
}
