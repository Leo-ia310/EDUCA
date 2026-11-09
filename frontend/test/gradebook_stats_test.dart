import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/grades/domain/gradebook_stats.dart';
import 'package:educa360/features/grades/domain/grades_repository.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

const scale = GradingScale(
  id: '1',
  name: '100',
  type: ScaleType.numeric,
  minValue: 0,
  maxValue: 100,
  passValue: 60,
  decimals: 1,
  ranges: [],
);

Evaluation ev(String id, String period, double max, double weight,
        {DateTime? date,}) =>
    Evaluation(
      id: id,
      classId: 1,
      subjectName: 'Mate',
      periodId: period,
      title: 'E$id',
      date: date ?? DateTime(2026, 3, 1),
      maxScore: max,
      weight: weight,
    );

AcademicPeriod period(String id, double weight) => AcademicPeriod(
      id: id,
      name: 'P$id',
      startDate: DateTime(2026),
      endDate: DateTime(2026, 12),
      weight: weight,
    );

void main() {
  final evals = [
    ev('1', 'a', 20, 1),
    ev('2', 'a', 100, 3),
    ev('3', 'b', 10, 1),
  ];
  final matrix = GradebookMatrix(
    evaluations: evals,
    students: const [
      (studentId: 1, name: 'Ana'),
      (studentId: 2, name: 'Beto'),
    ],
    grades: const {
      1: {'1': 20, '2': 80, '3': 5},
      2: {'1': null, '2': null, '3': null},
    },
  );

  test('promedio de periodo: ponderado por el peso de cada evaluación', () {
    final r = summarizeStudents(
      matrix: matrix,
      evaluations: evals.take(2).toList(),
      scale: scale,
      yearMode: false,
    );
    // (100*1 + 80*3) / 4 = 85
    expect(r[0].average, closeTo(85, 1e-9));
    expect(r[0].best, 100);
    expect(r[0].worst, 80);
    expect(r[1].average, isNull);
    expect(r[1].gradedCount, 0);
  });

  test('acumulado del año: primero por periodo y luego por peso de periodo',
      () {
    final r = summarizeStudents(
      matrix: matrix,
      evaluations: evals,
      scale: scale,
      yearMode: true,
      periods: [period('a', 1), period('b', 3)],
    );
    // a = 85, b = 50 → (85*1 + 50*3) / 4 = 58.75
    expect(r[0].average, closeTo(58.75, 1e-9));
    expect(r[0].gradedCount, 3);
  });

  test('año: oculta evaluaciones futuras sin notas pero no las que ya tienen',
      () {
    final future = DateTime(2030);
    final m = GradebookMatrix(
      evaluations: [
        ev('1', 'a', 10, 1),
        ev('2', 'a', 10, 1, date: future),
        ev('3', 'a', 10, 1, date: future),
      ],
      students: const [(studentId: 1, name: 'Ana')],
      grades: const {
        1: {'1': 5, '2': null, '3': 9},
      },
    );
    final shown = visibleEvaluations(m, yearMode: true, now: DateTime(2026));
    expect(shown.map((e) => e.id), ['1', '3']);
    expect(visibleEvaluations(m, yearMode: false).length, 3);
  });
}
