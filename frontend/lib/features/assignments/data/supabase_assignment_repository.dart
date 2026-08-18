import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/assignment_repository.dart';
import '../domain/entities.dart';

/// Implementación Supabase del repositorio. Lee/escribe contra las tablas
/// `assignments`, `assignment_files`, `submissions`, `submission_files`,
/// `evaluations` y `grades` definidas en `backend/migrations/`.
class SupabaseAssignmentRepository implements AssignmentRepository {
  SupabaseAssignmentRepository({
    required SupabaseClient client,
    required this.institutionId,
  }) : _c = client;

  final SupabaseClient _c;
  final int institutionId;

  static const _assignmentSelect =
      'id, class_id, title, description, instructions, assigned_at, '
      'due_at, max_score, allow_late, published, '
      'classes(id, group_id, subjects(name), groups(name))';

  static const _submissionSelect =
      'id, assignment_id, student_id, submitted_at, student_notes, '
      'is_late, task_status_id, students(persons(first_name, last_name))';

  Map<String, int>? _taskStatusCache;
  Future<Map<String, int>> _taskStatusIds() async {
    final cached = _taskStatusCache;
    if (cached != null) return cached;
    final rows = await _c.from('catalog_task_statuses').select('id, code');
    final map = {
      for (final r in (rows as List))
        r['code'] as String: (r['id'] as num).toInt(),
    };
    _taskStatusCache = map;
    return map;
  }

  Future<List<int>> _classIdsForStudent(int studentId) async {
    final enrollments = await _c
        .from('enrollments')
        .select('group_id')
        .eq('student_id', studentId)
        .eq('institution_id', institutionId);
    final groupIds = (enrollments as List)
        .map((e) => (e['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (groupIds.isEmpty) return const [];
    final classes = await _c
        .from('classes')
        .select('id')
        .inFilter('group_id', groupIds)
        .eq('institution_id', institutionId);
    return (classes as List)
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  // ---------- Lectura ----------
  @override
  Future<List<Assignment>> assignmentsForTeacher({int? classId}) async {
    var query = _c
        .from('assignments')
        .select(_assignmentSelect)
        .eq('institution_id', institutionId)
        .filter('deleted_at', 'is', null);
    if (classId != null) query = query.eq('class_id', classId);
    final rows = await query.order('due_at');
    return Future.wait(
      (rows as List).cast<Map<String, dynamic>>().map(_hydrateAssignment),
    );
  }

  @override
  Future<List<Assignment>> assignmentsForStudent({int? studentId}) async {
    if (studentId == null) return const [];
    final classIds = await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return const [];
    final rows = await _c
        .from('assignments')
        .select(_assignmentSelect)
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId)
        .eq('published', true)
        .filter('deleted_at', 'is', null)
        .order('due_at');
    return Future.wait(
      (rows as List).cast<Map<String, dynamic>>().map(_hydrateAssignment),
    );
  }

  @override
  Future<Assignment?> assignmentById(String id) async {
    final row = await _c
        .from('assignments')
        .select(_assignmentSelect)
        .eq('id', id)
        .eq('institution_id', institutionId)
        .maybeSingle();
    return row == null ? null : await _hydrateAssignment(row);
  }

  @override
  Future<List<Submission>> submissionsForAssignment(
    String assignmentId,
  ) async {
    final rows = await _c
        .from('submissions')
        .select(_submissionSelect)
        .eq('assignment_id', assignmentId)
        .eq('institution_id', institutionId);
    final statuses = await _taskStatusIds();
    return Future.wait(
      (rows as List)
          .cast<Map<String, dynamic>>()
          .map((r) => _hydrateSubmission(r, statuses)),
    );
  }

  @override
  Future<Submission?> submissionForStudent({
    required String assignmentId,
    required int studentId,
  }) async {
    final row = await _c
        .from('submissions')
        .select(_submissionSelect)
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId)
        .maybeSingle();
    if (row == null) return null;
    final statuses = await _taskStatusIds();
    return _hydrateSubmission(row, statuses);
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
      'published': draft.published,
    };
    final row =
        await _c.from('assignments').upsert(payload).select('id').single();
    final assignmentId = row['id'].toString();

    if (draft.attachments.isNotEmpty) {
      await _linkAttachments(
        attachments: draft.attachments,
        assignmentId: assignmentId,
      );
    }

    final created = await assignmentById(assignmentId);
    return created ??
        (throw StateError('No se pudo recuperar la tarea creada'));
  }

  /// Enlaza adjuntos ya subidos (vía `SupabaseFileUploadService`, que sube a
  /// Storage y devuelve el id de la fila `files` como `AssignmentAttachment.id`)
  /// a la tarea o entrega correspondiente.
  Future<void> _linkAttachments({
    required List<AssignmentAttachment> attachments,
    String? assignmentId,
    String? submissionId,
  }) async {
    for (final a in attachments) {
      final fileId = int.tryParse(a.id);
      if (fileId == null) continue; // adjunto demo, sin fila real en `files`.
      if (assignmentId != null) {
        await _c.from('assignment_files').upsert(
          {'assignment_id': assignmentId, 'file_id': fileId},
          onConflict: 'assignment_id,file_id',
          ignoreDuplicates: true,
        );
      } else if (submissionId != null) {
        await _c.from('submission_files').upsert(
          {'submission_id': submissionId, 'file_id': fileId},
          onConflict: 'submission_id,file_id',
          ignoreDuplicates: true,
        );
      }
    }
  }

  @override
  Future<void> deleteAssignment(String id) async {
    await _c
        .from('assignments')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  @override
  Future<void> publishAssignment(String id, {required bool published}) async {
    await _c
        .from('assignments')
        .update({'published': published})
        .eq('id', id);
  }

  @override
  Future<Submission> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    final submissionRow = await _c
        .from('submissions')
        .select('id, assignment_id, student_id')
        .eq('id', submissionId)
        .single();
    final assignmentId = submissionRow['assignment_id'].toString();
    final studentId = (submissionRow['student_id'] as num).toInt();

    final assignmentRow = await _c
        .from('assignments')
        .select('class_id, academic_period_id, max_score, title')
        .eq('id', assignmentId)
        .single();

    final evaluationId = await _findOrCreateEvaluation(
      assignmentId: assignmentId,
      classId: (assignmentRow['class_id'] as num).toInt(),
      academicPeriodId: (assignmentRow['academic_period_id'] as num?)?.toInt(),
      maxScore: (assignmentRow['max_score'] as num?)?.toDouble(),
      title: assignmentRow['title'] as String?,
    );

    await _c.from('grades').upsert({
      'institution_id': institutionId,
      'evaluation_id': evaluationId,
      'student_id': studentId,
      'score': score,
      'notes': feedback,
    }, onConflict: 'evaluation_id,student_id');

    final statuses = await _taskStatusIds();
    final gradedStatusId = statuses['CALI'];
    await _c
        .from('submissions')
        .update({if (gradedStatusId != null) 'task_status_id': gradedStatusId})
        .eq('id', submissionId);

    final updated = await submissionForStudent(
      assignmentId: assignmentId,
      studentId: studentId,
    );
    return updated ??
        (throw StateError('Entrega no encontrada tras calificar'));
  }

  Future<String> _findOrCreateEvaluation({
    required String assignmentId,
    required int classId,
    int? academicPeriodId,
    double? maxScore,
    String? title,
  }) async {
    final existing = await _c
        .from('evaluations')
        .select('id')
        .eq('assignment_id', assignmentId)
        .maybeSingle();
    if (existing != null) return existing['id'].toString();

    final created = await _c
        .from('evaluations')
        .insert({
          'institution_id': institutionId,
          'class_id': classId,
          'academic_period_id': academicPeriodId,
          'assignment_id': assignmentId,
          'title': title,
          'max_score': maxScore,
          'published': true,
        })
        .select('id')
        .single();
    return created['id'].toString();
  }

  // ---------- Escritura estudiante ----------
  @override
  Future<Submission> submit({
    required String assignmentId,
    required int studentId,
    required List<AssignmentAttachment> attachments,
    String? notes,
  }) async {
    final statuses = await _taskStatusIds();
    final now = DateTime.now();

    final assignmentRow = await _c
        .from('assignments')
        .select('due_at')
        .eq('id', assignmentId)
        .single();
    final dueAt = DateTime.tryParse(assignmentRow['due_at'] as String? ?? '');
    final isLate = dueAt != null && now.isAfter(dueAt);

    final payload = {
      'institution_id': institutionId,
      'assignment_id': assignmentId,
      'student_id': studentId,
      'submitted_at': now.toIso8601String(),
      'student_notes': notes,
      'is_late': isLate,
      'task_status_id': statuses['ENTR'],
    };

    final row = await _c
        .from('submissions')
        .upsert(payload, onConflict: 'assignment_id,student_id')
        .select('id')
        .single();
    final submissionId = row['id'].toString();

    if (attachments.isNotEmpty) {
      await _linkAttachments(
        attachments: attachments,
        submissionId: submissionId,
      );
    }

    final created = await submissionForStudent(
      assignmentId: assignmentId,
      studentId: studentId,
    );
    return created ?? (throw StateError('No se pudo recuperar la entrega'));
  }

  // ---------- Counters ----------
  @override
  Future<({int pending, int submitted, int toGrade})>
      teacherCounters() async {
    final assigns = await assignmentsForTeacher();
    var pending = 0;
    var submitted = 0;
    var toGrade = 0;
    for (final a in assigns) {
      if (a.statusForNow(DateTime.now()) == AssignmentStatus.open) pending++;
      submitted += a.submittedCount;
      toGrade += (a.submittedCount - a.gradedCount).clamp(0, a.submittedCount);
    }
    return (pending: pending, submitted: submitted, toGrade: toGrade);
  }

  @override
  Future<({int pending, int submitted, int graded})> studentCounters({
    required int studentId,
  }) async {
    final classIds = await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return (pending: 0, submitted: 0, graded: 0);

    final assignments = await _c
        .from('assignments')
        .select('id')
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId)
        .eq('published', true)
        .filter('deleted_at', 'is', null);
    final assignmentIds =
        (assignments as List).map((a) => a['id'].toString()).toList();
    if (assignmentIds.isEmpty) return (pending: 0, submitted: 0, graded: 0);

    final submissions = await _c
        .from('submissions')
        .select('assignment_id, task_status_id')
        .inFilter('assignment_id', assignmentIds)
        .eq('student_id', studentId);
    final statuses = await _taskStatusIds();
    final gradedId = statuses['CALI'];
    final submittedAssignmentIds = (submissions as List)
        .map((s) => s['assignment_id'].toString())
        .toSet();
    final graded =
        submissions.where((s) => s['task_status_id'] == gradedId).length;
    final submitted = submittedAssignmentIds.length;
    final pending = assignmentIds.length - submitted;
    return (pending: pending, submitted: submitted, graded: graded);
  }

  // ---------- Hidratación ----------
  Future<Assignment> _hydrateAssignment(Map<String, dynamic> row) async {
    final cls = row['classes'] as Map<String, dynamic>?;
    final subject =
        (cls?['subjects'] as Map<String, dynamic>?)?['name'] as String? ??
            'Materia';
    final group =
        (cls?['groups'] as Map<String, dynamic>?)?['name'] as String? ??
            'Grupo';
    final groupId = (cls?['group_id'] as num?)?.toInt();
    final assignmentId = row['id'].toString();
    final statuses = await _taskStatusIds();
    final gradedId = statuses['CALI'];

    final results = await Future.wait([
      _attachmentsFor(
        table: 'assignment_files',
        column: 'assignment_id',
        id: assignmentId,
      ),
      groupId == null
          ? Future<List<dynamic>>.value(const [])
          : _c.from('enrollments').select('id').eq('group_id', groupId),
      _c
          .from('submissions')
          .select('id, task_status_id')
          .eq('assignment_id', assignmentId),
    ]);
    final attachments = results[0] as List<AssignmentAttachment>;
    final totalStudents = results[1].length;
    final submissionRows = results[2].cast<Map<String, dynamic>>();
    final gradedCount =
        submissionRows.where((s) => s['task_status_id'] == gradedId).length;

    return Assignment(
      id: assignmentId,
      classId: (row['class_id'] as num).toInt(),
      subjectName: subject,
      groupName: group,
      title: row['title'] as String,
      description: row['description'] as String?,
      instructions: row['instructions'] as String?,
      assignedAt: DateTime.tryParse(row['assigned_at'] as String? ?? '') ??
          DateTime.now(),
      dueAt: DateTime.parse(row['due_at'] as String),
      kind: AssignmentKind.homework,
      maxScore: (row['max_score'] as num?)?.toDouble() ?? 100,
      allowLate: row['allow_late'] as bool? ?? false,
      published: row['published'] as bool? ?? true,
      attachments: attachments,
      totalStudents: totalStudents,
      submittedCount: submissionRows.length,
      gradedCount: gradedCount,
    );
  }

  Future<Submission> _hydrateSubmission(
    Map<String, dynamic> row,
    Map<String, int> statuses,
  ) async {
    final person = ((row['students'] as Map?)?['persons'] as Map?) ?? const {};
    final fullName =
        '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'.trim();
    final isLate = row['is_late'] as bool? ?? false;
    final submissionId = row['id'].toString();
    final taskStatusId = row['task_status_id'] as int?;
    final isGraded = taskStatusId != null && taskStatusId == statuses['CALI'];

    final attachments = await _attachmentsFor(
      table: 'submission_files',
      column: 'submission_id',
      id: submissionId,
    );

    double? score;
    String? feedback;
    if (isGraded) {
      final evaluation = await _c
          .from('evaluations')
          .select('id')
          .eq('assignment_id', row['assignment_id'] as Object)
          .maybeSingle();
      if (evaluation != null) {
        final grade = await _c
            .from('grades')
            .select('score, notes')
            .eq('evaluation_id', evaluation['id'] as Object)
            .eq('student_id', row['student_id'] as Object)
            .maybeSingle();
        score = (grade?['score'] as num?)?.toDouble();
        feedback = grade?['notes'] as String?;
      }
    }

    return Submission(
      id: submissionId,
      assignmentId: row['assignment_id'].toString(),
      studentId: (row['student_id'] as num).toInt(),
      studentName: fullName.isEmpty ? 'Estudiante' : fullName,
      status: isGraded
          ? SubmissionStatus.graded
          : (isLate ? SubmissionStatus.late : SubmissionStatus.submitted),
      submittedAt: DateTime.tryParse(row['submitted_at'] as String? ?? ''),
      studentNotes: row['student_notes'] as String?,
      attachments: attachments,
      score: score,
      feedback: feedback,
    );
  }

  Future<List<AssignmentAttachment>> _attachmentsFor({
    required String table,
    required String column,
    required String id,
  }) async {
    final rows = await _c
        .from(table)
        .select('files(id, original_name, url, size_bytes, mime_type)')
        .eq(column, id);
    return (rows as List)
        .map((r) => r['files'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(
          (f) => AssignmentAttachment(
            id: f['id'].toString(),
            name: f['original_name'] as String? ?? 'archivo',
            url: f['url'] as String? ?? '',
            sizeBytes: (f['size_bytes'] as num?)?.toInt(),
            mimeType: f['mime_type'] as String?,
          ),
        )
        .toList();
  }
}
