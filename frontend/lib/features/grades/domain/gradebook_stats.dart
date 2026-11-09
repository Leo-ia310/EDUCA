import 'entities.dart';
import 'grades_repository.dart';

/// Valor del selector de periodo que significa «todo el año hasta hoy».
const kGradebookYear = 'year';

/// Resumen de un estudiante en el libro de notas (valores en la escala).
class StudentGradeSummary {
  const StudentGradeSummary({
    required this.studentId,
    required this.name,
    required this.average,
    required this.gradedCount,
    required this.totalCount,
    this.best,
    this.worst,
  });

  final int studentId;
  final String name;

  /// Promedio ponderado; `null` si aún no tiene ninguna nota.
  final double? average;
  final int gradedCount;
  final int totalCount;
  final double? best;
  final double? worst;

  int get missingCount => totalCount - gradedCount;
}

/// Evaluaciones que se muestran. En el acumulado del año se ocultan las que
/// todavía no ocurren y no tienen ninguna nota (columnas vacías futuras).
List<Evaluation> visibleEvaluations(
  GradebookMatrix matrix, {
  required bool yearMode,
  DateTime? now,
}) {
  if (!yearMode) return matrix.evaluations;
  final today = now ?? DateTime.now();
  final withGrades = <String>{
    for (final row in matrix.grades.values)
      for (final e in row.entries)
        if (e.value != null) e.key,
  };
  return [
    for (final e in matrix.evaluations)
      if (!e.date.isAfter(today) || withGrades.contains(e.id)) e,
  ];
}

/// Promedio ponderado de un conjunto de notas: Σ(nota normalizada · peso) / Σ(peso).
double? _weighted(
  Iterable<MapEntry<Evaluation, double>> scores,
  GradingScale scale,
) {
  var sum = 0.0;
  var weight = 0.0;
  for (final s in scores) {
    final w = s.key.weight <= 0 ? 1.0 : s.key.weight;
    sum += scale.normalize(s.value, rawMax: s.key.maxScore) * w;
    weight += w;
  }
  return weight == 0 ? null : sum / weight;
}

/// Calcula el resumen de cada estudiante. Con [yearMode] el promedio es el del
/// año hasta hoy: primero por periodo (según el peso de cada evaluación) y luego
/// entre periodos según el peso de cada uno, igual que el boletín.
List<StudentGradeSummary> summarizeStudents({
  required GradebookMatrix matrix,
  required List<Evaluation> evaluations,
  required GradingScale scale,
  required bool yearMode,
  List<AcademicPeriod> periods = const [],
}) {
  final periodWeight = {for (final p in periods) p.id: p.weight};
  return [
    for (final s in matrix.students)
      () {
        final entries = <MapEntry<Evaluation, double>>[];
        for (final e in evaluations) {
          final raw = matrix.grades[s.studentId]?[e.id];
          if (raw != null) entries.add(MapEntry(e, raw));
        }
        double? average;
        if (!yearMode) {
          average = _weighted(entries, scale);
        } else {
          final byPeriod = <String, List<MapEntry<Evaluation, double>>>{};
          for (final en in entries) {
            byPeriod.putIfAbsent(en.key.periodId, () => []).add(en);
          }
          var sum = 0.0;
          var weight = 0.0;
          for (final p in byPeriod.entries) {
            final score = _weighted(p.value, scale);
            if (score == null) continue;
            final w = (periodWeight[p.key] ?? 1) <= 0
                ? 1.0
                : (periodWeight[p.key] ?? 1);
            sum += score * w;
            weight += w;
          }
          average = weight == 0 ? null : sum / weight;
        }
        final normalized = [
          for (final en in entries)
            scale.normalize(en.value, rawMax: en.key.maxScore),
        ]..sort();
        return StudentGradeSummary(
          studentId: s.studentId,
          name: s.name,
          average: average,
          gradedCount: entries.length,
          totalCount: evaluations.length,
          best: normalized.isEmpty ? null : normalized.last,
          worst: normalized.isEmpty ? null : normalized.first,
        );
      }(),
  ];
}
