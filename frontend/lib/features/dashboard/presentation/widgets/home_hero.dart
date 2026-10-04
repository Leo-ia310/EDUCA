import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';

/// Hero de bienvenida del home (estudiante y docente): saludo + nombre + subtítulo alineados a la
/// izquierda, sobre una ilustración de fondo (mañana/tarde/noche) según la
/// hora del día.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.name,
    required this.subtitle,
  });

  final String name;
  final String subtitle;

  static String _backgroundFor(int hour) {
    if (hour < 12) return 'assets/images/hero_sky_morning.png';
    if (hour < 19) return 'assets/images/hero_sky_afternoon.png';
    return 'assets/images/hero_sky_night.png';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = DateUtilsX.greetingForHour(now);
    final textShadows = [
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
    ];

    // Altura de la zona de la barra superior (ancho completo); debajo, el hero
    // se estrecha con margen lateral y esquinas inferiores convexas.
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
      width: double.infinity,
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(_backgroundFor(now.hour), fit: BoxFit.cover),
          // Velo oscuro: arriba (para la barra superior) y a la izquierda
          // (para el texto), sobre la ilustración.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black38, Colors.transparent],
                stops: [0, 0.3],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.black38, Colors.transparent],
                stops: [0, 0.75],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  greeting,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2.2,
                    shadows: textShadows,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.displayMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    shadows: textShadows,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                    shadows: textShadows,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
