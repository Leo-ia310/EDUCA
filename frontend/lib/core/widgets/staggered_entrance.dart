import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/motion.dart';

/// Entra los hijos de una columna de forma escalonada (fade + leve deslizado
/// hacia arriba), uno tras otro. Parte de "Sereno en movimiento".
///
/// Se reproduce **una sola vez**: como es un [StatefulWidget], su estado
/// sobrevive a los rebuilds (p. ej. de Riverpod), así que la animación no se
/// vuelve a disparar y no distrae. Respeta "reducir movimiento".
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.itemDuration = AppMotion.base,
    this.stagger = AppMotion.stagger,
    this.slide = 14,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final Duration itemDuration;
  final Duration stagger;

  /// Desplazamiento vertical inicial, en píxeles.
  final double slide;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    // Ya animó (o el usuario pidió menos movimiento): render estático.
    if (_done || context.reduceMotion) {
      return Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        children: widget.children,
      );
    }

    final last = widget.children.length - 1;
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          widget.children[i]
              .animate(
                onComplete: i == last ? (_) => setState(() => _done = true) : null,
              )
              .fadeIn(
                duration: widget.itemDuration,
                delay: widget.stagger * i,
                curve: AppMotion.standard,
              )
              .slideY(
                begin: widget.slide / 100,
                end: 0,
                duration: widget.itemDuration,
                delay: widget.stagger * i,
                curve: AppMotion.standard,
              ),
      ],
    );
  }
}
