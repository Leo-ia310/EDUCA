import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/local_attendance.dart';
import '../models/local_class_session.dart';

/// Acceso a las tablas `class_sessions` y `attendances` de Supabase. Diseñado
/// para idempotencia: si el `uuid` ya existe en el server, hace UPDATE.
class AttendanceRemoteDataSource {
  AttendanceRemoteDataSource(this._client);
  final SupabaseClient _client;

  /// Sube (insert/update) una sesión. Devuelve el id del server.
  Future<int> upsertClassSession({
    required LocalClassSession session,
    required int institutionId,
  }) async {
    final payload = {
      'institution_id': institutionId,
      'class_id': session.classId,
      'group_id': null, // se completaría si el cliente conoce el group_id
      'date': DateTime.fromMillisecondsSinceEpoch(session.dateMs)
          .toIso8601String()
          .substring(0, 10),
      'recorded_by': session.teacherId,
      'synced': true,
    };
    final row = await _client
        .from('class_sessions')
        .upsert(payload)
        .select('id')
        .single();
    return row['id'] as int;
  }

  /// Sube (insert/update) un registro de asistencia identificado por uuid.
  Future<int> upsertAttendance({
    required LocalAttendance record,
    required int institutionId,
    int? classSessionServerId,
  }) async {
    final payload = {
      'uuid': record.uuid,
      'institution_id': institutionId,
      'class_session_id': classSessionServerId ?? record.classSessionId,
      'student_id': record.studentId,
      'attendance_status_id': record.statusId,
      'recorded_at':
          DateTime.fromMillisecondsSinceEpoch(record.recordedAtMs)
              .toIso8601String(),
      'notes': record.notes,
      'source': 'app',
    };
    final row = await _client
        .from('attendances')
        .upsert(payload, onConflict: 'uuid')
        .select('id')
        .single();
    return row['id'] as int;
  }
}
