import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/features/assignments/domain/entities.dart';

Assignment _assignment({
  bool published = true,
  DateTime? dueAt,
  int totalStudents = 30,
  int submittedCount = 0,
  int gradedCount = 0,
}) =>
    Assignment(
      id: '1',
      classId: 1,
      subjectName: 'Matemáticas',
      groupName: '4° A',
      title: 'Guía de práctica',
      assignedAt: DateTime(2026, 1, 1),
      dueAt: dueAt ?? DateTime(2026, 6, 1),
      kind: AssignmentKind.homework,
      maxScore: 100,
      allowLate: false,
      attachments: const [],
      totalStudents: totalStudents,
      submittedCount: submittedCount,
      gradedCount: gradedCount,
      published: published,
    );

void main() {
  final now = DateTime(2026, 5, 1, 12);

  group('Assignment.statusForNow', () {
    test('no publicada -> draft', () {
      expect(_assignment(published: false).statusForNow(now),
          AssignmentStatus.draft);
    });

    test('todas calificadas -> closed', () {
      expect(_assignment(totalStudents: 30, gradedCount: 30).statusForNow(now),
          AssignmentStatus.closed);
    });

    test('pasada la fecha -> overdue', () {
      expect(
          _assignment(dueAt: now.subtract(const Duration(hours: 1)))
              .statusForNow(now),
          AssignmentStatus.overdue);
    });

    test('vence en <= 48h -> dueSoon', () {
      expect(
          _assignment(dueAt: now.add(const Duration(hours: 24)))
              .statusForNow(now),
          AssignmentStatus.dueSoon);
    });

    test('vence lejos -> open', () {
      expect(
          _assignment(dueAt: now.add(const Duration(days: 10)))
              .statusForNow(now),
          AssignmentStatus.open);
    });

    test('closed tiene prioridad sobre overdue', () {
      expect(
          _assignment(
                  gradedCount: 30, dueAt: now.subtract(const Duration(days: 1)))
              .statusForNow(now),
          AssignmentStatus.closed);
    });
  });

  group('Assignment progreso', () {
    test('submissionProgress y gradingProgress', () {
      final a = _assignment(
          totalStudents: 20, submittedCount: 10, gradedCount: 5);
      expect(a.submissionProgress, 0.5);
      expect(a.gradingProgress, 0.5);
    });

    test('sin estudiantes/entregas devuelve 0 (sin dividir por cero)', () {
      final a = _assignment(totalStudents: 0);
      expect(a.submissionProgress, 0);
      expect(a.gradingProgress, 0);
    });
  });
}
