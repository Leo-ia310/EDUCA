import 'attendance_local_datasource.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../domain/entities.dart';
import '../models/local_attendance.dart';
import '../repositories/backend_sync_repository.dart';

/// Lecturas autorizadas y lotes de asistencia con versiones e idempotencia.
class AttendanceRemoteDataSource {
  AttendanceRemoteDataSource(this._api) : _sync = BackendSyncRepository(_api);

  final BackendApiClient _api;

  final BackendSyncRepository _sync;

  Future<List<ClassSessionBrief>> todaysClasses({
    required int teacherId,
  }) async {
    final response = await _api.call('assignments.teacherClasses');
    return ((response as List?) ?? const [])
        .map((row) => _classFromMap(Map<String, dynamic>.from(row as Map)))
        .where((c) => c.can('attendance.write'))
        .toList();
  }

  Future<List<StudentBrief>> classRoster(
      {required int classId,
      required int institutionId,
      required DateTime date,
      required AttendanceLocalDataSource local,}) async {
    final response = Map<String, dynamic>.from(await _api.get(
        '/attendance/class/$classId',
        queryParameters: {'date': dayKey(date)},) as Map,);
    final result = <StudentBrief>[];
    final hydrated = <LocalAttendance>[];
    for (final raw in response['students'] as List) {
      final row = Map<String, dynamic>.from(raw as Map),
          id = int.parse(row['studentId'].toString());
      result.add(StudentBrief(id: id, fullName: row['name'] as String));
      final previous =
          local.recordFor(classId: classId, studentId: id, date: date);
      if (previous != null && previous.syncStateIndex != 1) continue;
      if (row['statusId'] == null) {
        if (previous != null) await local.removeRecord(previous.uuid);
        continue;
      }
      final record = LocalAttendance(
          uuid: previous?.uuid ?? row['uuid'] as String,
          classDate: dayKey(date),
          classId: classId,
          studentId: id,
          statusId: int.parse(row['statusId'].toString()),
          recordedAtMs: date.millisecondsSinceEpoch,
          syncStateIndex: 1,
          notes: row['notes'] as String?,
          serverId: int.parse(row['attendanceId'].toString()),
          serverVersion: (row['version'] as num).toInt(),
          classSessionId: response['sessionId'] == null
              ? null
              : int.parse(response['sessionId'].toString()),);
      hydrated.add(record);
    }
    await local.upsertRecords(hydrated);
    return result;
  }

  Future<Map<String, dynamic>> uploadBatch(
          {required List<Map<String, dynamic>> sessions,
          required List<Map<String, dynamic>> marks,}) async =>
      Map<String, dynamic>.from(await _api.post('/sync/attendance/batch',
          data: {'sessions': sessions, 'marks': marks},) as Map,);

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> syncQueue({String? status}) async {
    final page = await _sync.listQueue(status: status);
    return page.items;
  }

  Future<Map<String, dynamic>> retrySyncQueue(int id) => _sync.retry(id);

  Future<Map<String, dynamic>> markSyncQueueFailed(int id, {String? error}) {
    return _sync.markFailed(id, error: error);
  }

  Future<Map<String, dynamic>> pullSyncChanges({DateTime? since}) {
    return _sync.pullChanges(since: since);
  }

  ClassSessionBrief _classFromMap(Map<String, dynamic> row) {
    return ClassSessionBrief(
      isOwner: row['isOwner'] == true,
      permissions: Set<String>.from(row['permissions'] as List? ?? []),
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
}
