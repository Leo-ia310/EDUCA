import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
///
/// Dirección "Pastel neutro" (rediseño v2): se retiró el verde de marca (salvia)
/// en favor de un AZUL como acento único, con neutros sin sesgo de color y
/// fondos casi-puros (blanco en claro, casi-negro en oscuro). El COLOR lo aporta
/// la paleta pastel por materia. Los tokens de marca se llaman accent/accentDeep/
/// accentSoft (antes lime*), expuestos vía [AppPalette] para que toda la app
/// herede el acento sin colores hardcodeados en pantallas.
class AppColors {
  AppColors._();

  // Marca — azul (acento único). Claro.
  static const Color accent = Color(0xFF4C8DF5); // rellenos grandes + botones
  static const Color accentDeep = Color(0xFF2E6BD6); // acento en primer plano (links, íconos, foco)
  static const Color accentSoft = Color(0xFFE4EDFC); // chips/pastillas y fondos de ícono

  // Marca — variantes para modo oscuro (más luminosas sobre fondos profundos).
  static const Color accentDark = Color(0xFF6FA8FF);
  static const Color accentDeepDark = Color(0xFF9CC4FF);
  static const Color accentSoftDark = Color(0xFF17263F);

  // Light — neutros puros (sin sesgo de color). Fondo blanco.
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F3F6);
  static const Color textLight = Color(0xFF1A1D21);
  static const Color textLightMuted = Color(0xFF6B7280);
  static const Color lineLight = Color(0xFFE6E8EC);
  static const Color lineLightSoft = Color(0xFFEEF0F3);

  // Dark — neutros casi-negros (sin sesgo de color).
  static const Color darkBg = Color(0xFF0E0E10);
  static const Color darkSurface = Color(0xFF17181B);
  static const Color darkSurfaceAlt = Color(0xFF1E2024);
  static const Color textDark = Color(0xFFECEEF1);
  static const Color textDarkMuted = Color(0xFF9AA0A8);
  static const Color lineDark = Color(0xFF2A2C31);

  // Semánticos — desaturados para no "chillar", pero legibles. El verde queda
  // reservado exclusivamente para estados de éxito (pagado/aprobado/presente).
  static const Color success = Color(0xFF4FA97B);
  static const Color warning = Color(0xFFD79A4E);
  static const Color danger = Color(0xFFD46A5E);
  static const Color info = Color(0xFF6E9BC6);

  // Acentos pastel para materias/roles.
  static const Color pastelSky = Color(0xFF8FB2C9);
  static const Color pastelLavender = Color(0xFFA9A3CE);
  static const Color pastelPeach = Color(0xFFE0B48F);
  static const Color pastelRose = Color(0xFFD79FA8);
  static const Color pastelMint = Color(0xFF8FC7AC);

  // Superficie destacada oscura (neutra) para héroes/bloques.
  static const Color cardCharcoal = Color(0xFF1B1D22);
}
