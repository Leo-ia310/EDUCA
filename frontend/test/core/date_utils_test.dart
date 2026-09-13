import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/core/utils/date_utils.dart';

void main() {
  group('DateUtilsX.hhmmToMinutes', () {
    test('convierte HH:MM a minutos desde medianoche', () {
      expect(DateUtilsX.hhmmToMinutes('00:00'), 0);
      expect(DateUtilsX.hhmmToMinutes('08:30'), 510);
      expect(DateUtilsX.hhmmToMinutes('23:59'), 1439);
    });

    test('tolera formatos incompletos o inválidos', () {
      expect(DateUtilsX.hhmmToMinutes('9'), 540); // solo la hora
      expect(DateUtilsX.hhmmToMinutes(''), 0);
      expect(DateUtilsX.hhmmToMinutes('ab:cd'), 0);
    });
  });

  group('DateUtilsX.greetingForHour', () {
    test('saluda según la franja del día', () {
      expect(DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 8)), 'Buenos días');
      expect(
          DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 15)), 'Buenas tardes');
      expect(
          DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 21)), 'Buenas noches');
    });

    test('límites de franja: 12 pasa a tarde, 19 pasa a noche', () {
      expect(DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 11, 59)),
          'Buenos días');
      expect(
          DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 12)), 'Buenas tardes');
      expect(DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 18, 59)),
          'Buenas tardes');
      expect(
          DateUtilsX.greetingForHour(DateTime(2026, 1, 1, 19)), 'Buenas noches');
    });
  });
}
