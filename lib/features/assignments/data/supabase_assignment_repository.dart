import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/assignment_repository.dart';
import '../domain/entities.dart';

/// Implementación Supabase del repositorio. Lee/escribe contra las tablas
/// `assignments`, `assignment_files`, `submissions`, `submission_files` y
/// `evaluations` definidas en `supabase/migrations/0002_init_academic_extras.sql`.
///
/// Esta clase es funcional pero está incompleta: faltan joins de subject_name
/// / group_name y la integración con `evaluations`/`grades` para que el
/// score persistido también aparezca en boletines. Marcado con `TODO` donde
/// debe extenderse al conectar a Supabase real.
class SupabaseAssignmentRepository implements AssignmentRepository {
  SupabaseAssignmentRepository({
    required SupabaseClient client,
    required this.institutionId,
  }) : _c = client;

  final SupabaseClient _c;
  final int institutionId;

  // ---------- Lectura ----------
  @override
  Future<List<Assignment>> assignmentsForTeacher({int? classId}) async {
    var query = _c
        .from('assignments')
        .select(
          'id, class_id, title, description, instructions, assigned_at, '
          'due_at, max_score, allow_late, '
          'classes(id, subjects(name), groups(name))',
        )
        .eq('institution_id', institutionId)
        .filter('deleted_at', 'is', null);
    if (classId != null) query = query.eq('class_id', classId);
    final rows = await query.order('due_at');
    return rows.map<Assignment>(_assignmentFromRow).toList();
  }

  @override
  Future<List<Assignment>> assignmentsForStudent({int? studentId}) async {
    // TODO: filtrar por enrollment del estudiante en clases activas.
    return assignmentsForTeacher();
  }

  @override
  Future<Assignment?> assignmentById(String id) async {
    final row = await _c
        .from('assignments')
        .select(
          'id, class_id, title, description, instructions, assigned_at, '
          'due_at, max_score, allow_late, '
          'classes(id, subjects(name), groups(name))',
        )
        .eq('id', id)
        .eq('institution_id', institutionId)
        .maybeSingle();
    return row == null ? null : _assignmentFromRow(row);
  }

  @override
  Future<List<Submission>> submissionsForAssignment(String assignmentId) async {
    final rows = await _c
        .from('submissions')
        .select(
          'id, assignment_id, student_id, submitted_at, student_notes, '
          'is_late, students(persons(first_name, last_name))',
        )
        .eq('assignment_id', assignmentId)
        .eq('institution_id', institutionId);
    return rows.map<Submission>(_submissionFromRow).toList();
  }

  @override
  Future<Submission?> submissionForStudent({
    required String assignmentId,
    required int studentId,
  }) async {
    final row = await _c
        .from('submissions')
        .select(
          'id, assignment_id, student_id, submitted_at, student_notes, '
          'is_late, students(persons(first_name, last_name))',
        )
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId)
        .maybeSingle();
    return row == null ? null : _submissionFromRow(row);
  }

  // ---------- Escritura docente ----------
  @override
  Future<Assignment> upsertAssignment(AssignmentDraft draft) async {
    final payload = {
      if (draft.assignmentId != null) 'id': draft.assignmentId,
      'institution_id': institutionId,
      'class_id': draft.classId,
      'title': draft.title,
      'description': draft.description,
      'instructions': draft.instructions,
      'due_at': draft.dueAt.toIso8601String(),
      'max_score': draft.maxScore,
      'allow_late': draft.allowLate,
    };
    final row = await _c
        .from('assignments')
        .upsert(payload)
        .select('id')
        .single();

    // TODO: persistir attachments en `assignment_files` y subir vía
    //       SupabaseFileUploadService (`folder: assignments/{id}`).
    return assignmentById(row['id'].toString()) ??
        (throw StateError('No se pudo recuperar la tarea creada'));
  }

  @override
  Future<void> deleteAssignment(String id) async {
    await _c.from('assignments').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Future<void> publishAssignment(String id, {required bool published}) async {
    // TODO: introducir columna `published` en `assignments` y migrar.
  }

  @override
  Future<Submission> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    // TODO: crear/actualizar `evaluations` + `grades` consistentes con la
    //       escala configurada por colegio.
    throw UnimplementedError(
      'gradeSubmission: pendiente de mapear a evaluations/grades',
    );
  }

  // ---------- Escritura estudiante ----------
  @override
  Future<Submission> submit({
    required String assignmentId,
    required int studentId,
    required List<AssignmentAttachment> attachments,
    String? notes,
  }) async {
    // TODO: insertar en submissions + submission_files.
    throw UnimplementedError(
      'submit: pendiente de subir attachments a Storage y persistir filas',
    );
  }

  // ---------- Counters ----------
  @override
  Future<({int pending, int submitted, int toGrade})> teacherCounters() async {
    final assigns = await assignmentsForTeacher();
    var pending = 0;
    for (final a in assigns) {
      if (a.statusForNow(DateTime.now()) == AssignmentStatus.open) pending++;
    }
    return (pending: pending, submitted: 0, toGrade: 0);
  }

  @override
  Future<({int pending, int submitted, int graded})> studentCounters({
    required int studentId,
  }) async {
    return (pending: 0, submitted: 0, graded: 0);
  }

  // ---------- Mappers ----------
  Assignment _assignmentFromRow(Map<String, dynamic> row) {
    final cls = row['classes'] as Map<String, dynamic>?;
    final subject =
        (cls?['subjects'] as Map<String, dynamic>?)?['name'] as String? ??
            'Materia';
    final group =
        (cls?['groups'] as Map<String, dynamic>?)?['name'] as String? ??
            'Grupo';
    return Assignment(
      id: row['id'].toString(),
      classId: (row['class_id'] as num).toInt(),
      subjectName: subject,
      groupName: group,
      title: row['title'] as String,
      description: row['description'] as String?,
      instructions: row['instructions'] as String?,
      assignedAt:
          DateTime.tryParse(row['assigned_at'] as String? ?? '') ?? DateTime.now(),
      dueAt: DateTime.parse(row['due_at'] as String),
      kind: AssignmentKind.homework,
      maxScore: (row['max_score'] as num?)?.toDouble() ?? 100,
      allowLate: row['allow_late'] as bool? ?? false,
      attachments: const [], // TODO: leer assignment_files
      totalStudents: 0, // TODO: count via enrollments
      submittedCount: 0,
      gradedCount: 0,
    );
  }

  Submission _submissionFromRow(Map<String, dynamic> row) {
    final person = ((row['students'] as Map?)?['persons'] as Map?) ?? const {};
    final fullName = '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'.trim();
    final isLate = row['is_late'] as bool? ?? false;
    return Submission(
      id: row['id'].toString(),
      assignmentId: row['assignment_id'].toString(),
      studentId: (row['student_id'] as num).toInt(),
      studentName: fullName.isEmpty ? 'Estudiante' : fullName,
      status:
          isLate ? SubmissionStatus.late : SubmissionStatus.submitted,
      submittedAt: DateTime.tryParse(row['submitted_at'] as String? ?? ''),
      studentNotes: row['student_notes'] as String?,
      attachments: const [], // TODO: leer submission_files
    );
  }
}
