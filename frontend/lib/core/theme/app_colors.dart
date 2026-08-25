import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
///
/// Dirección "Sereno" (rediseño v1): el lima eléctrico evolucionó a un salvia
/// suave y los neutros se volvieron cálidos. Los NOMBRES de los tokens se
/// conservan (lime/limeDeep/limeSoft) para que toda la app herede el cambio
/// sin editar pantallas.
class AppColors {
  AppColors._();

  // Marca — salvia (evolución desaturada del lima). Claro.
  static const Color limePrimary = Color(0xFFA7BE6B); // rellenos grandes + acento sobre charcoal
  static const Color limeDeep = Color(0xFF6E8340); // acento en primer plano (links, íconos)
  static const Color limeSoft = Color(0xFFE7EDD5); // chips/pastillas y fondos de ícono

  // Marca — variantes para modo oscuro (más luminosas sobre fondos profundos).
  static const Color limePrimaryDark = Color(0xFFB7CA80);
  static const Color limeDeepDark = Color(0xFFC9D99A);
  static const Color limeSoftDark = Color(0xFF2A311A);

  // Light — neutros cálidos con leve sesgo verde.
  static const Color lightBg = Color(0xFFF4F6EF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEDEFE4);
  static const Color textLight = Color(0xFF23281E);
  static const Color textLightMuted = Color(0xFF6E7565);
  static const Color lineLight = Color(0xFFE4E7DA);
  static const Color lineLightSoft = Color(0xFFECEFE3);

  // Dark — neutros cálidos.
  static const Color darkBg = Color(0xFF15180F);
  static const Color darkSurface = Color(0xFF1C2015);
  static const Color darkSurfaceAlt = Color(0xFF22271A);
  static const Color textDark = Color(0xFFECEFE1);
  static const Color textDarkMuted = Color(0xFFA6AD97);
  static const Color lineDark = Color(0xFF2D3222);

  // Semánticos — desaturados para no "chillar", pero legibles.
  static const Color success = Color(0xFF4FA97B);
  static const Color warning = Color(0xFFD79A4E);
  static const Color danger = Color(0xFFD46A5E);
  static const Color info = Color(0xFF6E9BC6);

  // Acentos pastel para materias/roles (uso opcional en fases siguientes).
  static const Color pastelSky = Color(0xFF8FB2C9);
  static const Color pastelLavender = Color(0xFFA9A3CE);
  static const Color pastelPeach = Color(0xFFE0B48F);
  static const Color pastelRose = Color(0xFFD79FA8);
  static const Color pastelMint = Color(0xFF8FC7AC);

  // Superficie destacada oscura (salvia profunda cálida) para héroes/bloques.
  static const Color cardCharcoal = Color(0xFF232A1B);
}
