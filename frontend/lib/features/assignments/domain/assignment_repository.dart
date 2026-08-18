import 'entities.dart';

/// Acceso a tareas y entregas. Multi-tenant: el `institutionId` lo resuelve
/// la implementación a partir del usuario autenticado.
abstract class AssignmentRepository {
  // -------- Lectura --------
  Future<List<Assignment>> assignmentsForTeacher({int? classId});
  Future<List<Assignment>> assignmentsForStudent({int? studentId});
  Future<Assignment?> assignmentById(String id);

  Future<List<Submission>> submissionsForAssignment(String assignmentId);
  Future<Submission?> submissionForStudent({
    required String assignmentId,
    required int studentId,
  });

  // -------- Escritura docente --------
  Future<Assignment> upsertAssignment(AssignmentDraft draft);
  Future<void> deleteAssignment(String id);
  Future<void> publishAssignment(String id, {required bool published});

  Future<Submission> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  });

  // -------- Escritura estudiante --------
  Future<Submission> submit({
    required String assignmentId,
    required int studentId,
    required List<AssignmentAttachment> attachments,
    String? notes,
  });

  /// Resumen rápido para badges (pendientes/por calificar) usado por
  /// dashboards.
  Future<({int pending, int submitted, int toGrade})> teacherCounters();
  Future<({int pending, int submitted, int graded})> studentCounters({
    required int studentId,
  });
}
