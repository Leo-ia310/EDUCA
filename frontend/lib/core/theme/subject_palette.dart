import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Acentos pastel estables por materia: el mismo nombre recibe siempre el mismo
/// color, de modo que cada asignatura tenga identidad visual propia sin tener
/// que configurarla en los datos. Parte de la dirección "Sereno".
const List<Color> _subjectPastels = <Color>[
  AppColors.pastelSky,
  AppColors.pastelLavender,
  AppColors.pastelPeach,
  AppColors.pastelRose,
  AppColors.pastelMint,
];

int _hash(String name) => name
    .toLowerCase()
    .trim()
    .codeUnits
    .fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);

/// Color pastel de la materia (para barras de progreso, puntos, rellenos).
Color subjectColor(String name) {
  if (name.trim().isEmpty) return AppColors.pastelSky;
  return _subjectPastels[_hash(name) % _subjectPastels.length];
}

/// Versión profunda del pastel, legible como ícono/texto sobre un tinte suave.
Color subjectInk(String name) =>
    Color.lerp(subjectColor(name), const Color(0xFF1A1D21), 0.42)!;

/// Fondo suave (tinte) del color de la materia, para pastillas de ícono.
Color subjectSoft(String name) => subjectColor(name).withValues(alpha: 0.16);

/// Superficies derivadas de un color base para el estilo "pastel + círculo
/// vívido" del panel del alumno: [surface] es un fondo muy claro, [vivid] es
/// una versión saturada para el círculo del ícono, e [ink]/[inkMuted] son
/// tintas legibles sobre el pastel. Unifica el criterio en todo el panel.
class PastelSurface {
  const PastelSurface({
    required this.vivid,
    required this.surface,
    required this.ink,
    required this.inkMuted,
  });

  final Color vivid;
  final Color surface;
  final Color ink;
  final Color inkMuted;
}

const Color _pastelInk = Color(0xFF232A33);

/// Deriva las superficies pastel/vívidas a partir de un color base (HSL),
/// sensible al tema: en claro la superficie es un tinte muy claro con tinta
/// oscura; en oscuro es un tinte oscuro de la materia con tinta clara. El
/// círculo [vivid] es idéntico en ambos temas. En widgets prefiere
/// `context.pastel(base)`, que toma el brillo del tema automáticamente.
PastelSurface pastelSurface(Color base,
    {Brightness brightness = Brightness.light,}) {
  final hsl = HSLColor.fromColor(base);
  final vivid = hsl
      .withSaturation(hsl.saturation.clamp(0.5, 1.0))
      .withLightness(0.56)
      .toColor();
  if (brightness == Brightness.dark) {
    final surface = hsl
        .withSaturation(hsl.saturation.clamp(0.30, 0.55))
        .withLightness(0.20)
        .toColor();
    final ink = hsl
        .withSaturation(hsl.saturation.clamp(0.25, 0.60))
        .withLightness(0.90)
        .toColor();
    return PastelSurface(
      vivid: vivid,
      surface: surface,
      ink: ink,
      inkMuted: ink.withValues(alpha: 0.66),
    );
  }
  final surface = hsl
      .withSaturation(hsl.saturation.clamp(0.35, 1.0))
      .withLightness(0.94)
      .toColor();
  return PastelSurface(
    vivid: vivid,
    surface: surface,
    ink: _pastelInk,
    inkMuted: _pastelInk.withValues(alpha: 0.62),
  );
}

/// Superficies pastel sensibles al tema del contexto. Uso: `context.pastel(c)`.
extension PastelSurfaceX on BuildContext {
  PastelSurface pastel(Color base) =>
      pastelSurface(base, brightness: Theme.of(this).brightness);
}

/// Atajo: superficies pastel (tema claro) para una materia por su nombre.
PastelSurface subjectSurface(String name) => pastelSurface(subjectColor(name));
