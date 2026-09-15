import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Degradados compartidos del producto. Centralizados para que todos los heros
/// (saludo de los dashboards, perfil) usen exactamente el mismo tratamiento y
/// no se dupliquen en cada pantalla.
class AppGradients {
  AppGradients._();

  /// Banda multicolor de los heros: azul → morado → teal, en diagonal.
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.accent, AppColors.heroPurple, AppColors.heroTeal],
  );
}
