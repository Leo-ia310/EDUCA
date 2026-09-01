import 'package:flutter/material.dart';

/// Tokens de movimiento de la dirección "Sereno en movimiento".
///
/// Una escala fija de duraciones y curvas —igual que la escala tipográfica—
/// para que toda la app se sienta parte del mismo material. Úsalos siempre en
/// vez de duraciones/curvas sueltas.
class AppMotion {
  AppMotion._();

  // Duraciones
  static const Duration xfast = Duration(milliseconds: 120); // press, toggles, hover
  static const Duration fast = Duration(milliseconds: 180); // chips, tooltips
  static const Duration base = Duration(milliseconds: 260); // entrada de tarjetas, fades
  static const Duration slow = Duration(milliseconds: 400); // páginas, container transform

  // Curvas
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Escalonado por defecto entre elementos de una lista.
  static const Duration stagger = Duration(milliseconds: 40);
}

/// Accesibilidad y rendimiento del movimiento.
///
/// `context.reduceMotion` respeta la preferencia del sistema ("reducir
/// movimiento"); `context.motion(d)` devuelve la duración normal o cero si el
/// usuario pidió menos movimiento, para degradar cualquier animación a un
/// cambio instantáneo (o a un fade simple donde aplique).
extension MotionX on BuildContext {
  bool get reduceMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;

  Duration motion(Duration d) => reduceMotion ? Duration.zero : d;
}
