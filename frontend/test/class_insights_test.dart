import 'package:educa360/features/dashboard/data/class_insights.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _enrol(int id, String first, String last,
        {String? code,}) =>
    {
      'students': {
        'id': id,
        'student_code': code,
        'persons': {'first_name': first, 'last_name': last},
      },
    };

Map<String, dynamic> _mark(int student, int status) =>
    {'student_id': student, 'attendance_status_id': status};

Map<String, dynamic> _grade(int student, num score, num max) => {
      'student_id': student,
      'score': score,
      'evaluations': {'max_score': max},
    };

void main() {
  group('buildStudentInsights', () {
    test('calcula asistencia y promedio por estudiante y ordena por nombre',
        () {
      final list = buildStudentInsights(
        enrollments: [
          _enrol(2, 'Beto', 'Zuniga', code: 'B-2'),
          _enrol(1, 'Ana', 'Perez', code: 'A-1'),
        ],
        attendances: [
          // Ana: 2 presentes, 1 tarde, 1 ausente → 3/4
          _mark(1, 1), _mark(1, 1), _mark(1, 3), _mark(1, 2),
          // Beto: 1 presente, 1 justificada, 2 ausentes → 2/4
          _mark(2, 1), _mark(2, 4), _mark(2, 2), _mark(2, 2),
        ],
        grades: [
          _grade(1, 17, 20), // 85
          _grade(1, 9, 10), // 90
          _grade(2, 10, 20), // 50
        ],
      );

      expect(list.map((s) => s.fullName), ['Ana Perez', 'Beto Zuniga']);
      final ana = list[0];
      expect((ana.present, ana.late, ana.absent, ana.sessions), (2, 1, 1, 4));
      expect(ana.attendanceRate, closeTo(0.75, 1e-9));
      expect(ana.gradeAverage, closeTo(87.5, 1e-9));
      expect(ana.gradedCount, 2);
      final beto = list[1];
      expect(beto.justified, 1);
      expect(beto.attendanceRate, closeTo(0.5, 1e-9));
      expect(beto.gradeAverage, closeTo(50, 1e-9));
    });

    test('sin marcas ni notas no inventa porcentajes', () {
      final list = buildStudentInsights(
        enrollments: [_enrol(1, 'Ana', 'Perez')],
        attendances: const [],
        grades: const [],
      );
      expect(list.single.attendanceRate, isNull);
      expect(list.single.gradeAverage, isNull);
      expect(list.single.atRisk, isFalse);
    });

    test('un estudiante matriculado dos veces aparece una sola vez', () {
      final list = buildStudentInsights(
        enrollments: [_enrol(1, 'Ana', 'Perez'), _enrol(1, 'Ana', 'Perez')],
        attendances: const [],
        grades: const [],
      );
      expect(list.length, 1);
    });

    test('ignora notas sin puntaje o con máximo inválido', () {
      final list = buildStudentInsights(
        enrollments: [_enrol(1, 'Ana', 'Perez')],
        attendances: const [],
        grades: [
          {
            'student_id': 1,
            'score': null,
            'evaluations': {'max_score': 20},
          },
          _grade(1, 5, 0),
          _grade(1, 15, 20), // 75
        ],
      );
      expect(list.single.gradeAverage, closeTo(75, 1e-9));
      expect(list.single.gradedCount, 1);
    });

    test('en riesgo: asistencia menor a 80 % o promedio menor a 60', () {
      final list = buildStudentInsights(
        enrollments: [
          _enrol(1, 'Al', 'Dia'),
          _enrol(2, 'Falta', 'Mucho'),
          _enrol(3, 'Nota', 'Baja'),
        ],
        attendances: [
          for (var i = 0; i < 10; i++) _mark(1, 1),
          for (var i = 0; i < 7; i++) _mark(2, 1),
          for (var i = 0; i < 3; i++) _mark(2, 2), // 70 %
          for (var i = 0; i < 10; i++) _mark(3, 1),
        ],
        grades: [_grade(1, 18, 20), _grade(2, 18, 20), _grade(3, 8, 20)],
      );
      final byName = {for (final s in list) s.fullName: s};
      expect(byName['Al Dia']!.atRisk, isFalse);
      expect(byName['Falta Mucho']!.atRisk, isTrue);
      expect(byName['Nota Baja']!.atRisk, isTrue);
    });
  });

  group('classSlotsFrom', () {
    test('toma solo los bloques de la clase y los ordena por día y hora', () {
      final slots = classSlotsFrom(
        [
          {
            'kind': 'class',
            'classId': '5',
            'weekdayIndex': 2,
            'startTime': '10:00',
            'endTime': '11:00',
            'room': 'A',
          },
          {
            'kind': 'class',
            'classId': '5',
            'weekdayIndex': 0,
            'startTime': '08:00',
            'endTime': '09:00',
            'room': null,
          },
          {
            'kind': 'class',
            'classId': '9',
            'weekdayIndex': 0,
            'startTime': '07:00',
            'endTime': '08:00',
          },
          {
            'kind': 'break',
            'classId': '5',
            'weekdayIndex': 1,
            'startTime': '09:00',
            'endTime': '09:30',
          },
        ],
        5,
      );
      expect(slots.map((s) => (s.weekdayIndex, s.start)),
          [(0, '08:00'), (2, '10:00')],);
      expect(slots[0].room, isNull);
      expect(slots[1].room, 'A');
    });

    test('con una respuesta inválida devuelve una lista vacía', () {
      expect(classSlotsFrom(null, 5), isEmpty);
      expect(classSlotsFrom('x', 5), isEmpty);
    });
  });

  group('nextClassSlot', () {
    ClassWeekSlot slot(int day, String start, String end) =>
        ClassWeekSlot(weekdayIndex: day, start: start, end: end);

    // 2026-11-09 es lunes (weekday 1 → índice 0).
    test('una clase de hoy que aún no empieza es la próxima (hoy)', () {
      final next = nextClassSlot(
        [slot(0, '14:00', '15:00'), slot(2, '08:00', '09:00')],
        DateTime(2026, 11, 9, 10, 0),
      );
      expect(next!.daysAhead, 0);
      expect(next.slot.start, '14:00');
    });

    test('una clase de hoy en curso todavía cuenta como hoy', () {
      final next = nextClassSlot(
          [slot(0, '09:30', '10:30')], DateTime(2026, 11, 9, 10, 0),);
      expect(next!.daysAhead, 0);
    });

    test('si la de hoy ya terminó, pasa al siguiente bloque de la semana', () {
      final next = nextClassSlot(
        [slot(0, '08:00', '09:00'), slot(2, '10:00', '11:00')],
        DateTime(2026, 11, 9, 12, 0),
      );
      expect(next!.daysAhead, 2); // miércoles
      expect(next.slot.start, '10:00');
    });

    test('si es el único bloque y ya pasó, vuelve en 7 días', () {
      final next = nextClassSlot(
          [slot(0, '08:00', '09:00')], DateTime(2026, 11, 9, 12, 0),);
      expect(next!.daysAhead, 7);
    });

    test('sin bloques no hay próxima clase', () {
      expect(nextClassSlot(const [], DateTime(2026, 11, 9)), isNull);
    });
  });
}
