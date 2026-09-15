import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/core/theme/subject_palette.dart';

void main() {
  group('subjectColor', () {
    test('es determinista: mismo nombre da el mismo color', () {
      expect(subjectColor('Matemáticas'), subjectColor('Matemáticas'));
    });

    test('normaliza mayúsculas y espacios', () {
      expect(subjectColor('  matemáticas '), subjectColor('Matemáticas'));
    });

    test('nombre vacío o en blanco cae al color de respaldo', () {
      expect(subjectColor(''), subjectColor('   '));
    });
  });

  group('pastelSurface (sensible al tema)', () {
    const base = Color(0xFF4C8DF5);
    final light = pastelSurface(base, brightness: Brightness.light);
    final dark = pastelSurface(base, brightness: Brightness.dark);

    test('el círculo vívido es idéntico en ambos temas', () {
      expect(light.vivid, dark.vivid);
    });

    test('la superficie cambia y es más oscura en modo oscuro', () {
      expect(light.surface, isNot(dark.surface));
      expect(dark.surface.computeLuminance(),
          lessThan(light.surface.computeLuminance()),);
    });

    test('la tinta es más clara en oscuro (texto sobre fondo oscuro)', () {
      expect(dark.ink.computeLuminance(),
          greaterThan(light.ink.computeLuminance()),);
    });
  });
}
