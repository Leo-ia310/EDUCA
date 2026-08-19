import '../../../../core/network/backend_api_client.dart';
import '../models/local_attendance.dart';
import '../models/local_class_session.dart';

/// Acceso a las tablas `class_sessions` y `attendances` de Supabase. Diseñado
/// para idempotencia: si el `uuid` ya existe en el server, hace UPDATE.
class AttendanceRemoteDataSource {
  AttendanceRemoteDataSource(this._api);
  final BackendApiClient _api;

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
}
