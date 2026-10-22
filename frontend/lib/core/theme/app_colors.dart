import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
///
/// Dos identidades, una por tema:
/// - **Claro: azul y blanco.** Azul real (`#2563EB`) como color de marca sobre
///   blanco, con un azul marino como tinta (texto, bordes y sombras duras).
/// - **Oscuro: estilo Discord.** Grises neutros en capas (fondo, tarjeta,
///   elevado), bordes y sombras duras oscuras —igual que en claro, donde son
///   azul marino sobre blanco— y un único acento «blurple». Todas las tarjetas
///   comparten la misma superficie; el color de categoría solo tiñe íconos,
///   ilustraciones y estados.
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

  // ── Oscuro · marca «blurple» (inspirado en Discord) ──────────────────────
  static const Color accentDark = Color(0xFF5865F2); // rellenos y botones
  static const Color accentDeepDark = Color(0xFF949CF7); // texto/íconos sobre oscuro
  static const Color accentSoftDark = Color(0xFF3C4270);
  static const Color barDark = Color(0xFF232428); // barras superior e inferior
  static const Color barDeepDark = Color(0xFF1B1C1F);
  static const Color onAccentDark = Color(0xFFFFFFFF); // texto sobre el acento

  // ── Oscuro · neutros (grises en capas: fondo → tarjeta → elevado) ────────
  static const Color darkBg = Color(0xFF1E1F22);
  static const Color darkSurface = Color(0xFF2B2D31);
  static const Color darkSurfaceAlt = Color(0xFF313338);
  static const Color textDark = Color(0xFFF2F3F5);
  static const Color textDarkMuted = Color(0xFFB5BAC1);
  static const Color lineDark = Color(0xFF3F4147);
  static const Color inkDark = Color(0xFF000000); // bordes y sombra dura (oscuros, como en claro)

  // ── Oscuro · acentos de contraste ────────────────────────────────────────
  static const Color sunDark = Color(0xFFF0B232);
  static const Color coralDark = Color(0xFFF2765F);
  static const Color mintDark = Color(0xFF3BA55D);
  static const Color grapeDark = Color(0xFFA78BFA);

  // ── Semánticos ───────────────────────────────────────────────────────────
  // Claro.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF0EA5E9);
  // Oscuro (más luminosos y con la misma saturación que los acentos).
  static const Color successDark = Color(0xFF23A55A);
  static const Color warningDark = Color(0xFFF0B232);
  static const Color dangerDark = Color(0xFFF23F42);
  static const Color infoDark = Color(0xFF00A8FC);

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
