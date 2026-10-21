import '../../../portal_access/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/provider_cache.dart';

import '../../domain/entities.dart';
import '../../providers.dart';

class StudentGradesArgs {
  const StudentGradesArgs({required this.studentId, this.periodId});
  final int studentId;
  final String? periodId;

  // Igualdad por valor: sin esto, cada rebuild crea un provider nuevo en el
  // `family` y la pantalla queda cargando para siempre.
  @override
  bool operator ==(Object other) =>
      other is StudentGradesArgs &&
      other.studentId == studentId &&
      other.periodId == periodId;

  @override
  int get hashCode => Object.hash(studentId, periodId);
}

/// Rendimiento por materia para un estudiante.
final studentPerformanceProvider = FutureProvider.autoDispose
    .family<List<SubjectPerformance>, int>((ref, studentId) async {
  final repo = ref.watch(gradesRepositoryProvider);
  final scale = ref.watch(defaultScaleProvider.future);
  return ref.cacheAfter(
    scale,
    (value) => repo.performanceForStudent(studentId: studentId, scale: value),
  );
});

/// Boletín para un estudiante en un periodo (o anual).
final reportCardProvider = FutureProvider.autoDispose
    .family<ReportCard, StudentGradesArgs>((ref, args) async {
  final repo = ref.watch(gradesRepositoryProvider);
  final scale = ref.watch(defaultScaleProvider.future);
  final permissions = ref.watch(portalAccessProvider.future);
  return ref.cacheAfter(Future.wait<Object>([permissions, scale]),
      (values) async {
    final access = values[0] as PortalAccess;
    if (!access.can('reports.view') ||
        !access.gradeVisible(args.studentId, args.periodId)) {
      throw StateError(
        'Las notas o reportes de este periodo están restringidos por tu institución.',
      );
    }
    return repo.reportCardForStudent(
      studentId: args.studentId,
      periodId: args.periodId,
      scale: values[1] as GradingScale,
    );
  });
});

/// Evaluaciones detalladas de un estudiante (drill-down por materia).
final studentEvaluationsProvider = FutureProvider.autoDispose.family<
    ({List<Evaluation> evaluations, Map<String, double?> grades}),
    ({int studentId, int classId})>((ref, args) async {
  final repo = ref.watch(gradesRepositoryProvider);
  return ref.cacheFor(() async {
    final evals = await repo.evaluationsFor(
      studentId: args.studentId,
      classId: args.classId,
    );
    final grades = await repo.gradesFor(studentId: args.studentId);
    final gradeMap = <String, double?>{};
    for (final e in evals) {
      final g = grades
          .where((g) => g.evaluationId == e.id)
          .cast<GradeEntry?>()
          .firstOrNull;
      gradeMap[e.id] = g?.rawScore;
    }
    return (evaluations: evals, grades: gradeMap);
  }());
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
