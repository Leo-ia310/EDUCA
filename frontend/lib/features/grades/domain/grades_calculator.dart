import 'entities.dart';

/// Calcula notas ponderadas. Aislado del repositorio para poder testearlo
/// sin backend y para que la lógica sea reutilizable en la generación de
/// boletines PDF y en dashboards.
class GradesCalculator {
  const GradesCalculator();

  /// Nota del periodo para un estudiante en una clase.
  ///
  /// Fórmula: Σ(score/max * weight) / Σ(weights)
  /// - `evaluations`: todas las evaluaciones de la clase en ese periodo.
  /// - `grades`: notas del estudiante para esas evaluaciones (subset).
  PeriodGrade computePeriodGrade({
    required int studentId,
    required String subjectName,
    required String periodId,
    required List<Evaluation> evaluations,
    required List<GradeEntry> grades,
    required GradingScale scale,
  }) {
    if (evaluations.isEmpty) {
      return PeriodGrade(
        studentId: studentId,
        subjectName: subjectName,
        periodId: periodId,
        score: 0,
        qualitativeLabel: null,
        passed: false,
        evaluationCount: 0,
      );
    }
    final byId = {
      for (final g in grades.where((g) => g.studentId == studentId))
        g.evaluationId: g,
    };
    double weightedSum = 0;
    double totalWeight = 0;
    var count = 0;
    for (final e in evaluations) {
      final g = byId[e.id];
      if (g == null) continue;
      final normalized = scale.normalize(g.rawScore, rawMax: e.maxScore);
      weightedSum += normalized * e.weight;
      totalWeight += e.weight;
      count++;
    }
    if (totalWeight == 0) {
      return PeriodGrade(
        studentId: studentId,
        subjectName: subjectName,
        periodId: periodId,
        score: 0,
        qualitativeLabel: null,
        passed: false,
        evaluationCount: 0,
      );
    }
    final score = double.parse(
      (weightedSum / totalWeight).toStringAsFixed(scale.decimals),
    );
    return PeriodGrade(
      studentId: studentId,
      subjectName: subjectName,
      periodId: periodId,
      score: score,
      qualitativeLabel: scale.labelFor(score),
      passed: scale.isPassing(score),
      evaluationCount: count,
    );
  }

  /// Consolida el rendimiento anual por materia con base en las notas de
  /// periodo ya calculadas y la ponderación de cada periodo.
  SubjectPerformance computeSubjectPerformance({
    required String subjectName,
    required String teacherName,
    required Map<String, PeriodGrade> periodGrades,
    required List<AcademicPeriod> periods,
    required GradingScale scale,
  }) {
    final scores = <String, double>{
      for (final p in periods)
        p.id: periodGrades[p.id]?.score ?? 0,
    };
    double weighted = 0;
    double totalWeight = 0;
    var evaluationCount = 0;
    for (final p in periods) {
      final g = periodGrades[p.id];
      if (g == null || g.evaluationCount == 0) continue;
      weighted += g.score * p.weight;
      totalWeight += p.weight;
      evaluationCount += g.evaluationCount;
    }
    final finalScore = totalWeight == 0
        ? 0.0
        : double.parse(
            (weighted / totalWeight).toStringAsFixed(scale.decimals),
          );
    return SubjectPerformance(
      subjectName: subjectName,
      teacherName: teacherName,
      periodScores: scores,
      finalScore: finalScore,
      qualitativeLabel: scale.labelFor(finalScore),
      passed: scale.isPassing(finalScore),
      evaluationCount: evaluationCount,
    );
  }

  /// Promedio general (todas las materias). Ponderación uniforme.
  double overallAverage(Iterable<SubjectPerformance> subjects) {
    final valid = subjects.where((s) => s.evaluationCount > 0).toList();
    if (valid.isEmpty) return 0;
    final sum = valid.fold<double>(0, (a, s) => a + s.finalScore);
    return double.parse((sum / valid.length).toStringAsFixed(2));
  }
}
