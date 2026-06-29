import 'package:flutter/material.dart';

/// Paleta cruda del producto. NO uses estos colores directamente en widgets;
/// úsalos a través de [Theme.of(context).colorScheme] o los tokens en
/// [AppPalette].
class AppColors {
  AppColors._();

  // Marca
  static const Color limePrimary = Color(0xFFA7F000);
  static const Color limeDeep = Color(0xFF9BE000);
  static const Color limeSoft = Color(0xFFE6F8B8);

  // Light
  static const Color lightBg = Color(0xFFF7FAEA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F4E2);
  static const Color textLight = Color(0xFF1E2218);
  static const Color textLightMuted = Color(0xFF5C6354);

  // Dark
  static const Color darkBg = Color(0xFF11140D);
  static const Color darkSurface = Color(0xFF1B1F15);
  static const Color darkSurfaceAlt = Color(0xFF252A1C);
  static const Color textDark = Color(0xFFF4F8EA);
  static const Color textDarkMuted = Color(0xFFB6BCA8);

  // Semánticos
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Tarjetas oscuras destacadas (dashboard padre/admin)
  static const Color cardCharcoal = Color(0xFF1F2418);
}
