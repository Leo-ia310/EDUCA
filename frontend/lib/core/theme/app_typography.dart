import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Escala tipográfica de Educa360. Usa Plus Jakarta Sans para una vibra
/// moderna y juvenil. Devolvemos un [TextTheme] que se inyecta en
/// [AppTheme.lightTheme] y [AppTheme.darkTheme].
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color base, Color muted) {
    final jakarta = GoogleFonts.plusJakartaSansTextTheme();
    return jakarta.copyWith(
      displayLarge:
          jakarta.displayLarge?.copyWith(color: base, fontWeight: FontWeight.w800),
      displayMedium:
          jakarta.displayMedium?.copyWith(color: base, fontWeight: FontWeight.w800),
      displaySmall:
          jakarta.displaySmall?.copyWith(color: base, fontWeight: FontWeight.w700),
      headlineLarge:
          jakarta.headlineLarge?.copyWith(color: base, fontWeight: FontWeight.w700),
      headlineMedium:
          jakarta.headlineMedium?.copyWith(color: base, fontWeight: FontWeight.w700),
      headlineSmall:
          jakarta.headlineSmall?.copyWith(color: base, fontWeight: FontWeight.w700),
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
