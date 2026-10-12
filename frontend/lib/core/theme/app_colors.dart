import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
///
/// Dos identidades, una por tema:
/// - **Claro: azul y blanco.** Azul real (`#2563EB`) como color de marca sobre
///   blanco, con un azul marino como tinta (texto, bordes y sombras duras).
/// - **Oscuro: negro y verde.** Negro con un leve matiz verde como fondo y un
///   verde esmeralda como marca.
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

  // ── Oscuro · marca verde ──────────────────────────────────────────────────
  static const Color accentDark = Color(0xFF22C55E); // rellenos y botones
  static const Color accentDeepDark = Color(0xFF4ADE80); // sobre negro
  static const Color accentSoftDark = Color(0xFF0E2A1B);
  static const Color barDark = Color(0xFF15803D); // barras (texto blanco)
  static const Color barDeepDark = Color(0xFF0F5F2E);
  static const Color onAccentDark = Color(0xFF04130A); // texto sobre verde

  // ── Oscuro · neutros (negro con matiz verde) ─────────────────────────────
  static const Color darkBg = Color(0xFF050807);
  static const Color darkSurface = Color(0xFF0D1210);
  static const Color darkSurfaceAlt = Color(0xFF141B18);
  static const Color textDark = Color(0xFFE8F5EE);
  static const Color textDarkMuted = Color(0xFF8DA397);
  static const Color lineDark = Color(0xFF22302A);
  static const Color inkDark = Color(0xFFE8F5EE); // bordes y sombra dura

  // ── Oscuro · acentos de contraste ────────────────────────────────────────
  static const Color sunDark = Color(0xFFFACC15);
  static const Color coralDark = Color(0xFFFB7185);
  static const Color mintDark = Color(0xFF2DD4BF);
  static const Color grapeDark = Color(0xFFA78BFA);

  // ── Semánticos ───────────────────────────────────────────────────────────
  // Claro.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF0EA5E9);
  // Oscuro (más luminosos). En oscuro la marca ya es verde, así que el éxito
  // usa un esmeralda más frío para distinguirse.
  static const Color successDark = Color(0xFF34D399);
  static const Color warningDark = Color(0xFFFBBF24);
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
