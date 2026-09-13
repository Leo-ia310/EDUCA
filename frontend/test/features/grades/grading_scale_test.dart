import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/features/grades/domain/entities.dart';

GradingScale _scale({
  double min = 0,
  double max = 10,
  int decimals = 1,
  double pass = 6,
}) =>
    GradingScale(
      id: 's',
      name: '0-$max',
      type: ScaleType.numeric,
      minValue: min,
      maxValue: max,
      passValue: pass,
      decimals: decimals,
      ranges: const [],
    );

void main() {
  group('GradingScale.normalize', () {
    test('escala linealmente de 0-100 a 0-10', () {
      expect(_scale().normalize(100), 10.0);
      expect(_scale().normalize(0), 0.0);
      expect(_scale().normalize(50), 5.0);
    });

    test('respeta un rawMax distinto de 100', () {
      expect(_scale().normalize(10, rawMax: 20), 5.0);
    });

    test('clampa los valores fuera de rango [0, rawMax]', () {
      expect(_scale().normalize(150), 10.0);
      expect(_scale().normalize(-10), 0.0);
    });

    test('rawMax de 0 devuelve minValue (sin dividir por cero)', () {
      expect(_scale().normalize(50, rawMax: 0), 0.0);
    });

    test('redondea a los decimales de la escala', () {
      expect(_scale(decimals: 0).normalize(53), 5.0); // 5.3 -> 5
      expect(_scale(decimals: 1).normalize(55), 5.5);
    });
  });

  group('GradingScale.isPassing', () {
    test('compara contra passValue', () {
      expect(_scale(pass: 6).isPassing(6), isTrue);
      expect(_scale(pass: 6).isPassing(5.9), isFalse);
    });
  });
}
