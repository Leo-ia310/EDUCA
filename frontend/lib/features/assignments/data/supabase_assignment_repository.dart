import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/assignment_repository.dart';
import '../domain/assignment_page.dart';
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

  @override
  Future<AssignmentPage> assignmentPage({
    int? studentId,
    AssignmentQuery query = const AssignmentQuery(),
    String? cursor,
    int limit = 50,
  }) async {
    if (query.kinds != null && query.kinds!.isEmpty) {
      return const AssignmentPage(items: []);
    }
    final data = Map<String, dynamic>.from(
      await _api.get(
        studentId == null ? '/assignments/teacher' : '/assignments/student',
        queryParameters: {
          'studentId': studentId,
          'classId': query.classId,
          'search': query.search,
          'onlyOpen': query.onlyOpen,
          'subject': query.subject,
          'kinds': query.kinds?.map((kind) => kind.name).join(','),
          'cursor': cursor,
          'limit': limit,
        },
      ) as Map,
    );
    return AssignmentPage(
      items: (data['assignments'] as List)
          .map(
            (row) => _assignmentFromApi(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  static const _assignmentSelect =
      'id, class_id, title, description, instructions, assigned_at, '
      'due_at, kind, max_score, allow_late, published, '
      'classes(id, group_id, subjects(name), groups(name))';

  static const _submissionSelect =
      'id, assignment_id, student_id, submitted_at, student_notes, '
      'is_late, task_status_id, students(persons(first_name, last_name))';

  Future<Map<String, int>>? _taskStatusRequest;
  Future<Map<String, int>> _taskStatusIds() =>
      _taskStatusRequest ??= _loadTaskStatuses();
  Future<Map<String, int>> _loadTaskStatuses() async {
    try {
      final rows = await _c.from('catalog_task_statuses').select('id, code');
      return {
        for (final row in rows)
          row['code'] as String: (row['id'] as num).toInt(),
      };
    } catch (_) {
      _taskStatusRequest = null;
      rethrow;
    }
  }

  // ---------- Lectura ----------
  // Complete exports/counters retain the old list contract; interactive feeds
  // call assignmentPage and append pages without refetching earlier items.
  Future<List<Assignment>> _allAssignments({
    int? studentId,
    int? classId,
  }) async {
    final items = <Assignment>[];
    String? cursor;
    do {
      final page = await assignmentPage(
        studentId: studentId,
        query: AssignmentQuery(classId: classId),
        cursor: cursor,
        limit: 100,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return items;
  }

  @override
  Future<List<Assignment>> assignmentsForTeacher({int? classId}) =>
      _allAssignments(classId: classId);

  @override
  Future<List<Assignment>> assignmentsForStudent({int? studentId}) async {
    final id =
        studentId ?? (await _c.rpc('current_student_id') as num?)?.toInt();
    if (id == null) {
      throw StateError('Selecciona un estudiante para consultar sus tareas.');
    }
    return _allAssignments(studentId: id);
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
    final data = Map<String, dynamic>.from(
      await _api.get('/assignments/$assignmentId/submissions') as Map,
    );
    return (data['students'] as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['submissionId'] != null)
        .map(
          (row) => _submissionFromApi({
            ...row,
            'id': row['submissionId'],
            'assignmentId': assignmentId,
            'studentId': int.parse(row['studentId'].toString()),
            'studentName': row['name'],
            'studentNotes': row['notes'],
          }),
        )
        .toList();
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
      'idempotencyKey': draft.idempotencyKey,
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
    final data =
        Map<String, dynamic>.from(await _c.rpc('assignment_counters') as Map);
    return (
      pending: (data['pending'] as num).toInt(),
      submitted: (data['submitted'] as num).toInt(),
      toGrade: (data['toGrade'] as num).toInt()
    );
  }

  @override
  Future<({int pending, int submitted, int graded})> studentCounters({
    required int studentId,
  }) async {
    final data = Map<String, dynamic>.from(
      await _c.rpc('assignment_counters', params: {'p_student_id': studentId})
          as Map,
    );
    return (
      pending: (data['pending'] as num).toInt(),
      submitted: (data['submitted'] as num).toInt(),
      graded: (data['graded'] as num).toInt()
    );
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
    final assignmentId = row['id'].toString();
    final results = await Future.wait([
      _attachmentsFor(
        table: 'assignment_files',
        column: 'assignment_id',
        id: assignmentId,
      ),
      _c.rpc(
        'dashboard_assignment_counts',
        params: {
          'p_assignment_ids': [row['id']],
        },
      ).then<dynamic>((value) => value),
    ]);
    final attachments = results[0] as List<AssignmentAttachment>;
    final counts = (results[1] as List).cast<Map<String, dynamic>>();
    final stats = counts.isEmpty ? <String, dynamic>{} : counts.first;

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
      dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
      kind: _kindFromApi(row['kind'] as String?),
      maxScore: (row['max_score'] as num?)?.toDouble() ?? 100,
      allowLate: row['allow_late'] as bool? ?? false,
      published: row['published'] as bool? ?? true,
      attachments: attachments,
      totalStudents: (stats['total'] as num?)?.toInt() ?? 0,
      submittedCount: (stats['delivered'] as num?)?.toInt() ?? 0,
      gradedCount: (stats['graded'] as num?)?.toInt() ?? 0,
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
          .order('id', ascending: false)
          .limit(1)
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
      status: taskStatusId == statuses['PEND']
          ? SubmissionStatus.pending
          : isGraded
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
      classId: int.parse(row['classId'].toString()),
      subjectName: row['subjectName'] as String? ?? 'Materia',
      groupName: row['groupName'] as String? ?? 'Grupo',
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      instructions: row['instructions'] as String?,
      assignedAt: DateTime.tryParse(row['assignedAt'] as String? ?? '') ??
          DateTime.now(),
      dueAt: DateTime.tryParse(row['dueAt'] as String? ?? ''),
      kind: _kindFromApi(row['kind'] as String?),
      maxScore: (row['maxScore'] as num?)?.toDouble() ?? 100,
      allowLate: row['allowLate'] as bool? ?? false,
      published: row['published'] as bool? ?? true,
      attachments: _attachmentsFromApi(row['attachments']),
      totalStudents: (row['totalStudents'] as num?)?.toInt() ?? 0,
      submittedCount: (row['submittedCount'] as num?)?.toInt() ?? 0,
      gradedCount: (row['gradedCount'] as num?)?.toInt() ?? 0,
      teacherName: row['teacherName'] as String?,
      progress: row['progress'] == null
          ? null
          : _progressFromApi(Map<String, dynamic>.from(row['progress'] as Map)),
    );
  }

  AssignmentKind _kindFromApi(String? value) {
    for (final kind in AssignmentKind.values) {
      if (kind.name == value) return kind;
    }
    return AssignmentKind.homework;
  }

  AssignmentProgress _progressFromApi(Map<String, dynamic> row) =>
      AssignmentProgress(
        status: row['status'] == null
            ? null
            : SubmissionStatus.values
                .firstWhere((s) => s.name == row['status']),
        score: (row['score'] as num?)?.toDouble(),
      );

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
