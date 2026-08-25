import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Acentos pastel estables por materia: el mismo nombre recibe siempre el mismo
/// color, de modo que cada asignatura tenga identidad visual propia sin tener
/// que configurarla en los datos. Parte de la dirección "Sereno".
const List<Color> _subjectPastels = <Color>[
  AppColors.pastelSky,
  AppColors.pastelLavender,
  AppColors.pastelPeach,
  AppColors.pastelRose,
  AppColors.pastelMint,
  AppColors.limePrimary, // salvia
];

int _hash(String name) => name
    .toLowerCase()
    .trim()
    .codeUnits
    .fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);

/// Color pastel de la materia (para barras de progreso, puntos, rellenos).
Color subjectColor(String name) {
  if (name.trim().isEmpty) return AppColors.limePrimary;
  return _subjectPastels[_hash(name) % _subjectPastels.length];
}

/// Versión profunda del pastel, legible como ícono/texto sobre un tinte suave.
Color subjectInk(String name) =>
    Color.lerp(subjectColor(name), const Color(0xFF23281E), 0.34)!;

/// Fondo suave (tinte) del color de la materia, para pastillas de ícono.
Color subjectSoft(String name) => subjectColor(name).withValues(alpha: 0.16);
