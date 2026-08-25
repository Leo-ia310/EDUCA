import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Tokens semánticos añadidos al tema a través de [ThemeExtension].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surfaceAlt,
    required this.cardElevated,
    required this.cardContrast,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.lime,
    required this.limeDeep,
    required this.limeSoft,
  });

  final Color surfaceAlt;
  final Color cardElevated;
  final Color cardContrast;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color lime;
  final Color limeDeep;
  final Color limeSoft;

  @override
  AppPalette copyWith({
    Color? surfaceAlt,
    Color? cardElevated,
    Color? cardContrast,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? lime,
    Color? limeDeep,
    Color? limeSoft,
  }) {
    return AppPalette(
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      cardElevated: cardElevated ?? this.cardElevated,
      cardContrast: cardContrast ?? this.cardContrast,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      lime: lime ?? this.lime,
      limeDeep: limeDeep ?? this.limeDeep,
      limeSoft: limeSoft ?? this.limeSoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      cardContrast: Color.lerp(cardContrast, other.cardContrast, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      limeDeep: Color.lerp(limeDeep, other.limeDeep, t)!,
      limeSoft: Color.lerp(limeSoft, other.limeSoft, t)!,
    );
  }
}

/// Atajo: `context.palette` y `context.textTheme`.
extension AppThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}

class AppTheme {
  AppTheme._();

  /// Transiciones de página suaves (fade + leve deslizamiento) en todas las
  /// plataformas, para una navegación calmada. Parte del pulido "Sereno".
  static const PageTransitionsTheme _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary: AppColors.limeDeep,
      onPrimary: AppColors.textLight,
      primaryContainer: AppColors.limeSoft,
      onPrimaryContainer: AppColors.textLight,
      secondary: AppColors.limePrimary,
      onSecondary: AppColors.textLight,
      surface: AppColors.lightSurface,
      onSurface: AppColors.textLight,
      surfaceContainerHighest: AppColors.lightSurfaceAlt,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.lineLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.lightBg,
      canvasColor: AppColors.lightBg,
      pageTransitionsTheme: _transitions,
      splashColor: AppColors.limePrimary.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      hoverColor: AppColors.limeSoft.withValues(alpha: 0.5),
      textTheme:
          AppTypography.textTheme(AppColors.textLight, AppColors.textLightMuted),
      extensions: const [
        AppPalette(
          surfaceAlt: AppColors.lightSurfaceAlt,
          cardElevated: AppColors.lightSurface,
          cardContrast: AppColors.cardCharcoal,
          textMuted: AppColors.textLightMuted,
          success: AppColors.success,
          warning: AppColors.warning,
          danger: AppColors.danger,
          info: AppColors.info,
          lime: AppColors.limePrimary,
          limeDeep: AppColors.limeDeep,
          limeSoft: AppColors.limeSoft,
        ),
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.textLight,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lineLightSoft),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.limePrimary,
          foregroundColor: AppColors.textLight,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cardCharcoal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textLight,
          side: const BorderSide(color: AppColors.lineLight),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: AppColors.textLightMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lineLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.limeDeep, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSurfaceAlt,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textLight,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.limeDeep,
        unselectedItemColor: AppColors.textLightMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.limeDeep,
        foregroundColor: AppColors.textLight,
        elevation: 4,
        shape: CircleBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lineLight,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: AppColors.limePrimaryDark,
      onPrimary: AppColors.textLight,
      primaryContainer: AppColors.limeSoftDark,
      onPrimaryContainer: AppColors.limePrimaryDark,
      secondary: AppColors.limeDeepDark,
      onSecondary: AppColors.textLight,
      surface: AppColors.darkSurface,
      onSurface: AppColors.textDark,
      surfaceContainerHighest: AppColors.darkSurfaceAlt,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.lineDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      canvasColor: AppColors.darkBg,
      pageTransitionsTheme: _transitions,
      splashColor: AppColors.limePrimaryDark.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      hoverColor: AppColors.limeSoftDark.withValues(alpha: 0.6),
      textTheme:
          AppTypography.textTheme(AppColors.textDark, AppColors.textDarkMuted),
      extensions: const [
        AppPalette(
          surfaceAlt: AppColors.darkSurfaceAlt,
          cardElevated: AppColors.darkSurface,
          cardContrast: Color(0xFF0A0C07),
          textMuted: AppColors.textDarkMuted,
          success: AppColors.success,
          warning: AppColors.warning,
          danger: AppColors.danger,
          info: AppColors.info,
          lime: AppColors.limePrimaryDark,
          limeDeep: AppColors.limeDeepDark,
          limeSoft: AppColors.limeSoftDark,
        ),
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lineDark),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.limePrimaryDark,
          foregroundColor: AppColors.textLight,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0A0C07),
          foregroundColor: AppColors.textDark,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          side: const BorderSide(color: AppColors.lineDark),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(color: AppColors.textDarkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.limePrimaryDark, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurfaceAlt,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.limePrimaryDark,
        unselectedItemColor: AppColors.textDarkMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.limePrimaryDark,
        foregroundColor: AppColors.textLight,
        elevation: 4,
        shape: CircleBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lineDark,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
