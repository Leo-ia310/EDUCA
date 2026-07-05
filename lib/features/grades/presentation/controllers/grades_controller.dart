import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';

class StudentGradesArgs {
  const StudentGradesArgs({required this.studentId, this.periodId});
  final int studentId;
  final String? periodId;
}

/// Rendimiento por materia para un estudiante.
final studentPerformanceProvider = FutureProvider.autoDispose
    .family<List<SubjectPerformance>, int>((ref, studentId) async {
  final repo = ref.watch(gradesRepositoryProvider);
  final scale = await repo.defaultScale();
  return repo.performanceForStudent(studentId: studentId, scale: scale);
});

/// Boletín para un estudiante en un periodo (o anual).
final reportCardProvider = FutureProvider.autoDispose
    .family<ReportCard, StudentGradesArgs>((ref, args) async {
  final repo = ref.watch(gradesRepositoryProvider);
  final scale = await repo.defaultScale();
  return repo.reportCardForStudent(
    studentId: args.studentId,
    periodId: args.periodId,
    scale: scale,
  );
});

/// Evaluaciones detalladas de un estudiante (drill-down por materia).
final studentEvaluationsProvider = FutureProvider.autoDispose.family<
    ({List<Evaluation> evaluations, Map<String, double?> grades}),
    ({int studentId, int classId})>((ref, args) async {
  final repo = ref.watch(gradesRepositoryProvider);
  final evals =
      await repo.evaluationsFor(studentId: args.studentId, classId: args.classId);
  final grades = await repo.gradesFor(studentId: args.studentId);
  final gradeMap = <String, double?>{};
  for (final e in evals) {
    final g = grades.where((g) => g.evaluationId == e.id).cast<GradeEntry?>().firstOrNull;
    gradeMap[e.id] = g?.rawScore;
  }
  return (evaluations: evals, grades: gradeMap);
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
