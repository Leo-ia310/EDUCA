import 'package:flutter/material.dart';

/// Paleta **curada y armónica** de acentos por materia (Educa v3). Tonos
/// vibrantes pero de saturación/brillo emparentados, para que convivan sin
/// chocar. Cada materia conocida recibe un color con sentido; las demás caen de
/// forma estable en la misma paleta (mismo nombre → mismo color).
class SubjectPalette {
  SubjectPalette._();

  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const sky = Color(0xFF0EA5E9);
  static const cyan = Color(0xFF06B6D4);
  static const teal = Color(0xFF14B8A6);
  static const emerald = Color(0xFF22C55E);
  static const amber = Color(0xFFF59E0B);
  static const orange = Color(0xFFF97316);
  static const rose = Color(0xFFF43F5E);
  static const pink = Color(0xFFEC4899);
  static const fuchsia = Color(0xFFD946EF);

  /// Rueda de fallback (orden pensado para máxima separación de matiz entre
  /// vecinos consecutivos).
  static const wheel = <Color>[
    indigo, amber, teal, rose, sky, orange, violet, emerald, cyan, pink,
  ];
}

/// Mapeo por palabra clave del nombre de la materia a un color con sentido.
const Map<String, Color> _subjectKeywords = <String, Color>{
  'matem': SubjectPalette.indigo,
  'calcul': SubjectPalette.indigo,
  'algebra': SubjectPalette.indigo,
  'álgebra': SubjectPalette.indigo,
  'físic': SubjectPalette.cyan,
  'fisic': SubjectPalette.cyan,
  'quím': SubjectPalette.emerald,
  'quim': SubjectPalette.emerald,
  'biolog': SubjectPalette.teal,
  'natural': SubjectPalette.teal,
  'histor': SubjectPalette.amber,
  'geograf': SubjectPalette.sky,
  'social': SubjectPalette.sky,
  'liter': SubjectPalette.rose,
  'lengua': SubjectPalette.rose,
  'español': SubjectPalette.rose,
  'espanol': SubjectPalette.rose,
  'ingl': SubjectPalette.violet,
  'idioma': SubjectPalette.violet,
  'ética': SubjectPalette.pink,
  'etica': SubjectPalette.pink,
  'filosof': SubjectPalette.pink,
  'físic. educ': SubjectPalette.orange,
  'educación f': SubjectPalette.orange,
  'educacion f': SubjectPalette.orange,
  'deport': SubjectPalette.orange,
  'arte': SubjectPalette.fuchsia,
  'música': SubjectPalette.fuchsia,
  'musica': SubjectPalette.fuchsia,
  'informát': SubjectPalette.indigo,
  'informat': SubjectPalette.indigo,
  'comput': SubjectPalette.indigo,
};

int _hash(String name) => name
    .toLowerCase()
    .trim()
    .codeUnits
    .fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);

/// Color (vibrante y curado) de la materia. Primero busca por palabra clave;
/// si no encaja, cae de forma estable en la rueda curada.
Color subjectColor(String name) {
  final n = name.toLowerCase().trim();
  if (n.isEmpty) return SubjectPalette.indigo;
  for (final entry in _subjectKeywords.entries) {
    if (n.contains(entry.key)) return entry.value;
  }
  return SubjectPalette.wheel[_hash(name) % SubjectPalette.wheel.length];
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
