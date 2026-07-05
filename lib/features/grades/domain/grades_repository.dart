import 'entities.dart';

/// Acceso a notas y escalas del colegio actual.
abstract class GradesRepository {
  // ---------- Escalas ----------
  Future<List<GradingScale>> scales();
  Future<GradingScale> defaultScale();
  Future<GradingScale> upsertScale(GradingScale scale);
  Future<void> setDefaultScale(String id);

  // ---------- Periodos ----------
  Future<List<AcademicPeriod>> periods();

  // ---------- Evaluaciones y notas ----------
  Future<List<Evaluation>> evaluationsFor({
    required int studentId,
    String? periodId,
    int? classId,
  });

  Future<List<GradeEntry>> gradesFor({
    required int studentId,
    String? periodId,
  });

  /// Rendimiento consolidado por materia (todos los periodos del año).
  Future<List<SubjectPerformance>> performanceForStudent({
    required int studentId,
    GradingScale? scale,
  });

  /// Boletín para un estudiante en un periodo (o anual si `periodId==null`).
  Future<ReportCard> reportCardForStudent({
    required int studentId,
    String? periodId,
    GradingScale? scale,
  });

  /// Matriz de notas para el gradebook docente: para una clase y periodo,
  /// las evaluaciones y las notas de todos los estudiantes matriculados.
  Future<GradebookMatrix> gradebook({
    required int classId,
    required String periodId,
  });

  /// Escribe una nota en una evaluación (docente).
  Future<void> setGrade({
    required String evaluationId,
    required int studentId,
    required double rawScore,
    String? notes,
  });
}

/// Vista tabular para el gradebook.
class GradebookMatrix {
  const GradebookMatrix({
    required this.evaluations,
    required this.students,
    required this.grades,
  });

  final List<Evaluation> evaluations;
  final List<({int studentId, String name})> students;

  /// `grades[studentId][evaluationId] = rawScore`
  final Map<int, Map<String, double?>> grades;
}
