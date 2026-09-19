import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../domain/entities.dart';
import '../models/local_attendance.dart';
import '../models/local_class_session.dart';

/// Acceso a las tablas `class_sessions` y `attendances` de Supabase. Diseñado
/// para idempotencia: si el `uuid` ya existe en el server, hace UPDATE.
class AttendanceRemoteDataSource {
  AttendanceRemoteDataSource(this._api, this._client);

  final BackendApiClient _api;
  final SupabaseClient _client;

  Future<List<ClassSessionBrief>> todaysClasses({
    required int teacherId,
  }) async {
    if (teacherId <= 0) return const [];
    final response = await _api.call('assignments.teacherClasses');
    return ((response as List?) ?? const [])
        .map((row) => _classFromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<StudentBrief>> classRoster({
    required int classId,
    required int institutionId,
  }) async {
    final classRow = await _client
        .from('classes')
        .select('group_id')
        .eq('id', classId)
        .eq('institution_id', institutionId)
        .single();
    final groupId = (classRow['group_id'] as num).toInt();
    final rows = await _client
        .from('enrollments')
        .select(
          'students(id, student_code, persons(first_name, last_name, photo_url))',
        )
        .eq('group_id', groupId)
        .eq('institution_id', institutionId);
    final students = (rows as List)
        .map((row) => _studentFromMap(Map<String, dynamic>.from(row as Map)))
        .whereType<StudentBrief>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return students;
  }

  /// Sube (insert/update) una sesión. Devuelve el id del server.
  Future<int> upsertClassSession({
    required LocalClassSession session,
    required int institutionId,
  }) async {
    final response = await _api.call('attendance.upsertClassSession', {
      'uuid': session.uuid,
      'classId': session.classId,
      'dateMs': session.dateMs,
      'teacherId': session.teacherId,
      'createdAtMs': session.createdAtMs,
    });
    final data = Map<String, dynamic>.from(response as Map);
    return (data['id'] as num).toInt();
  }

  /// Sube (insert/update) un registro de asistencia identificado por uuid.
  Future<int> upsertAttendance({
    required LocalAttendance record,
    required int institutionId,
    int? classSessionServerId,
  }) async {
    final response = await _api.call('attendance.upsertAttendance', {
      'uuid': record.uuid,
      'classId': record.classId,
      'classSessionId': classSessionServerId ?? record.classSessionId,
      'studentId': record.studentId,
      'statusId': record.statusId,
      'recordedAtMs': record.recordedAtMs,
      'notes': record.notes,
    });
    final data = Map<String, dynamic>.from(response as Map);
    return (data['id'] as num).toInt();
  }

  ClassSessionBrief _classFromMap(Map<String, dynamic> row) {
    return ClassSessionBrief(
      classId: (row['classId'] as num).toInt(),
      groupId: (row['groupId'] as num).toInt(),
      subjectName: row['subjectName'] as String? ?? 'Materia',
      groupName: row['groupName'] as String? ?? 'Grupo',
      startTime: row['startTime'] as String? ?? '',
      endTime: row['endTime'] as String? ?? '',
      studentCount: (row['studentCount'] as num?)?.toInt() ?? 0,
      classroom: row['classroom'] as String?,
    );
  }

  StudentBrief? _studentFromMap(Map<String, dynamic> enrollment) {
    final student = enrollment['students'];
    if (student is! Map) return null;
    final person = student['persons'];
    final personMap = person is Map ? person : const {};
    final first = personMap['first_name'] as String? ?? '';
    final last = personMap['last_name'] as String? ?? '';
    final name = '$first $last'.trim();
    return StudentBrief(
      id: (student['id'] as num).toInt(),
      fullName: name.isEmpty ? 'Estudiante' : name,
      studentCode: student['student_code'] as String?,
      avatarUrl: personMap['photo_url'] as String?,
    );
  }
}
