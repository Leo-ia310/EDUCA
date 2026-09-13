import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/grades/domain/grades_calculator.dart';

const _scale = GradingScale(
  id: 's',
  name: '0-10',
  type: ScaleType.numeric,
  minValue: 0,
  maxValue: 10,
  passValue: 6,
  decimals: 1,
  ranges: [],
);

Evaluation _eval(String id,
        {double maxScore = 100, double weight = 1, String period = 'p1'}) =>
    Evaluation(
      id: id,
      classId: 1,
      subjectName: 'Matemáticas',
      periodId: period,
      title: 'Eval $id',
      date: DateTime(2026, 3, 1),
      maxScore: maxScore,
      weight: weight,
    );

GradeEntry _grade(String evalId, double raw, {int studentId = 7}) =>
    GradeEntry(evaluationId: evalId, studentId: studentId, rawScore: raw);

void main() {
  const calc = GradesCalculator();

  PeriodGrade compute(
          {required List<Evaluation> evals, required List<GradeEntry> grades}) =>
      calc.computePeriodGrade(
        studentId: 7,
        subjectName: 'Matemáticas',
        periodId: 'p1',
        evaluations: evals,
        grades: grades,
        scale: _scale,
      );

  group('GradesCalculator.computePeriodGrade', () {
    test('promedia ponderando por el peso de cada evaluación', () {
      // A: peso 1, 100/100 -> 10 ; B: peso 3, 60/100 -> 6
      // (10*1 + 6*3) / (1+3) = 28/4 = 7.0
      final g = compute(
        evals: [_eval('a', weight: 1), _eval('b', weight: 3)],
        grades: [_grade('a', 100), _grade('b', 60)],
      );
      expect(g.score, 7.0);
      expect(g.passed, isTrue);
      expect(g.evaluationCount, 2);
    });

    test('normaliza según el maxScore de cada evaluación', () {
      // maxScore 20, raw 10 -> 5.0 (en escala 0-10)
      final g = compute(
        evals: [_eval('a', maxScore: 20)],
        grades: [_grade('a', 10)],
      );
      expect(g.score, 5.0);
      expect(g.passed, isFalse);
    });

    test('ignora evaluaciones sin nota del estudiante', () {
      final g = compute(
        evals: [_eval('a', weight: 1), _eval('b', weight: 1)],
        grades: [_grade('a', 80)], // sin nota para b
      );
      expect(g.score, 8.0); // solo cuenta a
      expect(g.evaluationCount, 1);
    });

    test('sin evaluaciones -> 0, no aprobado, sin contar', () {
      final g = compute(evals: const [], grades: const []);
      expect(g.score, 0);
      expect(g.passed, isFalse);
      expect(g.evaluationCount, 0);
    });

    test('evaluaciones sin ninguna nota -> 0 (peso total 0)', () {
      final g = compute(evals: [_eval('a')], grades: const []);
      expect(g.score, 0);
      expect(g.evaluationCount, 0);
    });

    test('no mezcla notas de otro estudiante', () {
      final g = compute(
        evals: [_eval('a')],
        grades: [_grade('a', 100, studentId: 99)], // otro alumno
      );
      expect(g.score, 0);
      expect(g.evaluationCount, 0);
    });
  });
}
