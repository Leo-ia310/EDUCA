import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica de Educa360. Usa Plus Jakarta Sans para una vibra
/// moderna y juvenil. Devolvemos un [TextTheme] que se inyecta en
/// [AppTheme.lightTheme] y [AppTheme.darkTheme].
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color base, Color muted) {
    final jakarta = GoogleFonts.plusJakartaSansTextTheme();
    // Dirección "Sereno": disciplina de peso. El w800 se reserva para cifras y
    // títulos grandes; los encabezados intermedios respiran en 600–700, con un
    // leve tracking negativo para una lectura más elegante.
    return jakarta.copyWith(
      displayLarge: jakarta.displayLarge
          ?.copyWith(color: base, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displayMedium: jakarta.displayMedium
          ?.copyWith(color: base, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      displaySmall: jakarta.displaySmall
          ?.copyWith(color: base, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineLarge: jakarta.headlineLarge
          ?.copyWith(color: base, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineMedium:
          jakarta.headlineMedium?.copyWith(color: base, fontWeight: FontWeight.w600),
      headlineSmall:
          jakarta.headlineSmall?.copyWith(color: base, fontWeight: FontWeight.w600),
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
