import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/assignment_repository.dart';
import '../domain/entities.dart';

/// Implementación Supabase del repositorio. Lee/escribe contra las tablas
/// `assignments`, `assignment_files`, `submissions`, `submission_files`,
/// `evaluations` y `grades` definidas en `supabase/migrations/`.
class SupabaseAssignmentRepository implements AssignmentRepository {
  SupabaseAssignmentRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.institutionId,
  })  : _c = client,
        _api = api;

  final SupabaseClient _c;
  final BackendApiClient _api;
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
    final response = await _api.call('assignments.upsert', {
      'assignmentId': draft.assignmentId,
      'classId': draft.classId,
      'title': draft.title,
      'description': draft.description,
      'instructions': draft.instructions,
      'kind': draft.kind.name,
      'dueAt': draft.dueAt.toIso8601String(),
      'maxScore': draft.maxScore,
      'allowLate': draft.allowLate,
      'published': draft.published,
      'attachments': draft.attachments.map(_attachmentToApi).toList(),
    });
    final data = Map<String, dynamic>.from(response as Map);
    return _assignmentFromApi(
      Map<String, dynamic>.from(data['assignment'] as Map),
    );
  }

  @override
  Future<void> deleteAssignment(String id) async {
    await _api.call('assignments.delete', {'id': id});
  }

  @override
  Future<void> publishAssignment(String id, {required bool published}) async {
    await _api.call('assignments.publish', {
      'id': id,
      'published': published,
    });
  }

  @override
  Future<Submission> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    final response = await _api.call(
      'assignments.gradeSubmission',
      {
        'submissionId': submissionId,
        'score': score,
        'feedback': feedback,
      },
    );
    final data = Map<String, dynamic>.from(response as Map);
    return _submissionFromApi(
      Map<String, dynamic>.from(data['submission'] as Map),
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
    final response = await _api.call(
      'assignments.submit',
      {
        'assignmentId': assignmentId,
        'studentId': studentId,
        'attachments': attachments.map(_attachmentToApi).toList(),
        'notes': notes,
      },
    );
    final data = Map<String, dynamic>.from(response as Map);
    return _submissionFromApi(
      Map<String, dynamic>.from(data['submission'] as Map),
    );
  }

  // ---------- Counters ----------
  @override
  Future<({int pending, int submitted, int toGrade})> teacherCounters() async {
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
    final submittedAssignmentIds =
        (submissions as List).map((s) => s['assignment_id'].toString()).toSet();
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

  Map<String, dynamic> _attachmentToApi(AssignmentAttachment a) => {
        'id': a.id,
        'name': a.name,
        'url': a.url,
        'sizeBytes': a.sizeBytes,
        'mimeType': a.mimeType,
      };

  Assignment _assignmentFromApi(Map<String, dynamic> row) {
    return Assignment(
      id: row['id'].toString(),
      classId: (row['classId'] as num).toInt(),
      subjectName: row['subjectName'] as String? ?? 'Materia',
      groupName: row['groupName'] as String? ?? 'Grupo',
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      instructions: row['instructions'] as String?,
      assignedAt: DateTime.tryParse(row['assignedAt'] as String? ?? '') ??
          DateTime.now(),
      dueAt: DateTime.tryParse(row['dueAt'] as String? ?? '') ?? DateTime.now(),
      kind: _kindFromApi(row['kind'] as String?),
      maxScore: (row['maxScore'] as num?)?.toDouble() ?? 100,
      allowLate: row['allowLate'] as bool? ?? false,
      published: row['published'] as bool? ?? true,
      attachments: _attachmentsFromApi(row['attachments']),
      totalStudents: (row['totalStudents'] as num?)?.toInt() ?? 0,
      submittedCount: (row['submittedCount'] as num?)?.toInt() ?? 0,
      gradedCount: (row['gradedCount'] as num?)?.toInt() ?? 0,
      teacherName: row['teacherName'] as String?,
    );
  }

  AssignmentKind _kindFromApi(String? value) {
    for (final kind in AssignmentKind.values) {
      if (kind.name == value) return kind;
    }
    return AssignmentKind.homework;
  }

  Submission _submissionFromApi(Map<String, dynamic> row) {
    return Submission(
      id: row['id'].toString(),
      assignmentId: row['assignmentId'].toString(),
      studentId: (row['studentId'] as num).toInt(),
      studentName: row['studentName'] as String? ?? 'Estudiante',
      status: _submissionStatusFromApi(row['status'] as String?),
      submittedAt: DateTime.tryParse(row['submittedAt'] as String? ?? ''),
      studentNotes: row['studentNotes'] as String?,
      attachments: _attachmentsFromApi(row['attachments']),
      score: (row['score'] as num?)?.toDouble(),
      feedback: row['feedback'] as String?,
    );
  }

  SubmissionStatus _submissionStatusFromApi(String? value) {
    for (final status in SubmissionStatus.values) {
      if (status.name == value) return status;
    }
    return SubmissionStatus.submitted;
  }

  List<AssignmentAttachment> _attachmentsFromApi(dynamic value) {
    final rows = value is List ? value : const [];
    return rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map(
          (r) => AssignmentAttachment(
            id: r['id'].toString(),
            name: r['name'] as String? ?? 'archivo',
            url: r['url'] as String? ?? '',
            sizeBytes: (r['sizeBytes'] as num?)?.toInt(),
            mimeType: r['mimeType'] as String?,
          ),
        )
        .toList();
  }
}
