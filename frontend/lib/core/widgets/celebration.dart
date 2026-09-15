import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/subject_palette.dart';
import 'glass.dart';

/// Muestra una micro-celebración a pantalla completa: un estallido de
/// partículas de colores + una tarjeta con ícono y mensaje que entra con
/// rebote. Se auto-descarta. Respeta "reducir movimiento" (cae a un SnackBar).
void showCelebration(
  BuildContext context, {
  String message = '¡Listo! 🎉',
  IconData icon = Icons.celebration_rounded,
}) {
  if (context.reduceMotion) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CelebrationView(
      message: message,
      icon: icon,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _Particle {
  _Particle(this.angle, this.distance, this.color, this.size, this.rotation);
  final double angle;
  final double distance;
  final Color color;
  final double size;
  final double rotation;
}

class _CelebrationView extends StatefulWidget {
  const _CelebrationView({
    required this.message,
    required this.icon,
    required this.onDone,
  });

  final String message;
  final IconData icon;
  final VoidCallback onDone;

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView> {
  late final List<_Particle> _particles;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    const colors = SubjectPalette.wheel;
    _particles = List.generate(28, (i) {
      return _Particle(
        rnd.nextDouble() * 2 * pi,
        90 + rnd.nextDouble() * 150,
        colors[rnd.nextInt(colors.length)],
        6 + rnd.nextDouble() * 8,
        rnd.nextDouble() * pi,
      );
    });
    _timer = Timer(const Duration(milliseconds: 1900), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Partículas que salen disparadas desde el centro.
            for (final p in _particles)
              Container(
                width: p.size,
                height: p.size,
                decoration: BoxDecoration(
                  color: p.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
                  .animate()
                  .move(
                    begin: Offset.zero,
                    end: Offset(cos(p.angle) * p.distance,
                        sin(p.angle) * p.distance,),
                    duration: 900.ms,
                    curve: Curves.easeOutCubic,
                  )
                  .rotate(begin: 0, end: p.rotation, duration: 900.ms)
                  .fadeOut(delay: 600.ms, duration: 500.ms),
            // Tarjeta central de vidrio esmerilado con ícono + mensaje.
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon,
                        color: palette.accentDeep, size: 34,),
                  )
                      .animate()
                      .scaleXY(
                        begin: 0.4,
                        end: 1,
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: 200.ms),
                  const SizedBox(height: 12),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ).animate().fadeIn(delay: 150.ms).moveY(begin: 8, end: 0),
                ],
              ),
            )
                .animate()
                .scaleXY(
                  begin: 0.8,
                  end: 1,
                  duration: 400.ms,
                  curve: AppMotion.standard,
                )
                .fadeIn(duration: 250.ms)
                .then(delay: 1100.ms)
                .fadeOut(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
