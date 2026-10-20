import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
///
/// Dos identidades, una por tema:
/// - **Claro: azul y blanco.** Azul real (`#2563EB`) como color de marca sobre
///   blanco, con un azul marino como tinta (texto, bordes y sombras duras).
/// - **Oscuro: «Grafito azul».** Casi negro azulado como fondo, gris azulado
///   claro para bordes y sombras duras, y un único acento azul. Las tarjetas por
///   categoría se tiñen con su color al 20 % sobre la superficie.
///
/// Para que la interfaz no quede en solo dos colores, cada tema trae cuatro
/// **acentos de contraste** (sol, coral, menta y uva) que se usan en tarjetas,
/// etiquetas y estados. Los tokens de marca se llaman accent/accentDeep/
/// accentSoft y se exponen vía [AppPalette].
class AppColors {
  AppColors._();

  // ── Claro · marca azul ────────────────────────────────────────────────────
  static const Color accent = Color(0xFF2563EB); // rellenos grandes + botones
  static const Color accentDeep = Color(0xFF1D4ED8); // primer plano (links, íconos)
  static const Color accentSoft = Color(0xFFDCE8FF); // chips y fondos de ícono
  static const Color barLight = Color(0xFF2563EB); // barras superior e inferior
  static const Color barDeepLight = Color(0xFF1E40AF); // final del degradado

  // ── Claro · neutros (blanco + azul marino) ───────────────────────────────
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEEF4FF);
  static const Color textLight = Color(0xFF0B1B3A); // azul marino
  static const Color textLightMuted = Color(0xFF5B6B8C);
  static const Color lineLight = Color(0xFFDCE6F7);
  static const Color lineLightSoft = Color(0xFFE8EFFB);
  static const Color inkLight = Color(0xFF0B1B3A); // bordes y sombra dura

  // ── Claro · acentos de contraste ─────────────────────────────────────────
  static const Color sunLight = Color(0xFFF5A300); // ámbar
  static const Color coralLight = Color(0xFFFF6B4A);
  static const Color mintLight = Color(0xFF0FB5A0);
  static const Color grapeLight = Color(0xFF7C5CFA);

  // ── Oscuro · marca azul ───────────────────────────────────────────────────
  static const Color accentDark = Color(0xFF4F8CFF); // rellenos y botones
  static const Color accentDeepDark = Color(0xFF4F8CFF); // sobre fondo oscuro
  static const Color accentSoftDark = Color(0xFF172746);
  static const Color barDark = Color(0xFF1B2A4A); // barras (texto claro)
  static const Color barDeepDark = Color(0xFF151E33);
  static const Color onAccentDark = Color(0xFF0D1017); // texto sobre azul

  // ── Oscuro · neutros (casi negro azulado) ────────────────────────────────
  static const Color darkBg = Color(0xFF0D1017);
  static const Color darkSurface = Color(0xFF151A23);
  static const Color darkSurfaceAlt = Color(0xFF1D2430);
  static const Color textDark = Color(0xFFEEF2FA);
  static const Color textDarkMuted = Color(0xFF93A0B8);
  static const Color lineDark = Color(0xFF2A3345);
  static const Color inkDark = Color(0xFFDCE4F5); // bordes y sombra dura

  // ── Oscuro · acentos de contraste ────────────────────────────────────────
  static const Color sunDark = Color(0xFFF5B63D);
  static const Color coralDark = Color(0xFFFF7A63);
  static const Color mintDark = Color(0xFF2EC4B6);
  static const Color grapeDark = Color(0xFF9B87F5);

  // ── Semánticos ───────────────────────────────────────────────────────────
  // Claro.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF0EA5E9);
  // Oscuro (más luminosos y con la misma saturación que los acentos).
  static const Color successDark = Color(0xFF3DC98A);
  static const Color warningDark = Color(0xFFF5B63D);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF38BDF8);

  // Acentos pastel para materias/roles.
  static const Color pastelSky = Color(0xFF8FB2C9);
  static const Color pastelLavender = Color(0xFFA9A3CE);
  static const Color pastelPeach = Color(0xFFE0B48F);
  static const Color pastelRose = Color(0xFFD79FA8);
  static const Color pastelMint = Color(0xFF8FC7AC);

  // Acentos del degradado multicolor de los heros.
  static const Color heroPurple = Color(0xFF7C5CFA);
  static const Color heroTeal = Color(0xFF0FB5A0);

  // Superficie destacada oscura (neutra) para héroes/bloques.
  static const Color cardCharcoal = Color(0xFF0B1B3A);
}
