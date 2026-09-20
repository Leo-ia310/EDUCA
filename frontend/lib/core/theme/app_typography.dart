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
      headlineMedium: sora.headlineMedium?.copyWith(
          color: base, fontWeight: FontWeight.w700, height: 1.15,),
      headlineSmall: sora.headlineSmall?.copyWith(
          color: base, fontWeight: FontWeight.w700, height: 1.2,),
      // Títulos: interlineado compacto y leve tracking negativo → jerarquía
      // más marcada y elegante.
      titleLarge: jakarta.titleLarge?.copyWith(
          color: base,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -0.2,),
      titleMedium: jakarta.titleMedium?.copyWith(
          color: base,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: -0.1,),
      titleSmall: jakarta.titleSmall?.copyWith(
          color: base, fontWeight: FontWeight.w600, height: 1.3,),
      // Cuerpo: interlineado más aireado para lectura cómoda.
      bodyLarge: jakarta.bodyLarge?.copyWith(color: base, height: 1.5),
      bodyMedium: jakarta.bodyMedium?.copyWith(color: base, height: 1.45),
      bodySmall: jakarta.bodySmall?.copyWith(color: muted, height: 1.4),
      // Etiquetas: leve tracking positivo para que respiren.
      labelLarge: jakarta.labelLarge?.copyWith(
          color: base, fontWeight: FontWeight.w600, letterSpacing: 0.1,),
      labelMedium: jakarta.labelMedium?.copyWith(
          color: muted, fontWeight: FontWeight.w500, letterSpacing: 0.2,),
      labelSmall: jakarta.labelSmall?.copyWith(
          color: muted, fontWeight: FontWeight.w500, letterSpacing: 0.2,),
    );
  }
}
