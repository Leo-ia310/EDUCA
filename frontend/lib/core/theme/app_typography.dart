import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica de Educa360 (v3 "Depth & Data"). Pareja de fuentes:
/// **Sora** para los títulos y cifras grandes (carácter de marca, geométrica) y
/// **Plus Jakarta Sans** para títulos intermedios, cuerpo y etiquetas (lectura
/// cómoda). Devolvemos un [TextTheme] que se inyecta en los temas claro/oscuro.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color base, Color muted) {
    final jakarta = GoogleFonts.plusJakartaSansTextTheme();
    final sora = GoogleFonts.soraTextTheme(jakarta);
    // Sora manda en display/headline; el w800 se reserva para cifras y títulos
    // grandes, con leve tracking negativo para una lectura más elegante.
    return jakarta.copyWith(
      displayLarge: sora.displayLarge
          ?.copyWith(color: base, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displayMedium: sora.displayMedium
          ?.copyWith(color: base, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      displaySmall: sora.displaySmall
          ?.copyWith(color: base, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineLarge: sora.headlineLarge
          ?.copyWith(color: base, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineMedium:
          sora.headlineMedium?.copyWith(color: base, fontWeight: FontWeight.w700),
      headlineSmall:
          sora.headlineSmall?.copyWith(color: base, fontWeight: FontWeight.w700),
      titleLarge:
          jakarta.titleLarge?.copyWith(color: base, fontWeight: FontWeight.w700),
      titleMedium:
          jakarta.titleMedium?.copyWith(color: base, fontWeight: FontWeight.w600),
      titleSmall:
          jakarta.titleSmall?.copyWith(color: base, fontWeight: FontWeight.w600),
      bodyLarge: jakarta.bodyLarge?.copyWith(color: base),
      bodyMedium: jakarta.bodyMedium?.copyWith(color: base),
      bodySmall: jakarta.bodySmall?.copyWith(color: muted),
      labelLarge:
          jakarta.labelLarge?.copyWith(color: base, fontWeight: FontWeight.w600),
      labelMedium:
          jakarta.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w500),
      labelSmall:
          jakarta.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w500),
    );
  }
}
