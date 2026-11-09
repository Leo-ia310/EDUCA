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
    final classes = ((response as List?) ?? const [])
        .map((row) => _classFromMap(Map<String, dynamic>.from(row as Map)))
        .where((c) => c.can('attendance.write'))
        .toList();
    // El backend entrega las clases del maestro sin hora ni aula: se completan
    // con su horario de hoy. Si el horario no se puede consultar, se devuelven
    // tal cual (todas «de hoy»), sin bloquear el pase de lista.
    final today = await _todaySlots();
    if (today == null) return classes;
    final result = [
      for (final c in classes)
        today[c.classId] == null
            ? c.withToday(scheduledToday: false)
            : c.withToday(
                scheduledToday: true,
                startTime: today[c.classId]!.start,
                endTime: today[c.classId]!.end,
                classroom: today[c.classId]!.room,
              ),
    ]..sort((a, b) {
        if (a.scheduledToday != b.scheduledToday) {
          return a.scheduledToday ? -1 : 1;
        }
        final byTime = a.startTime.compareTo(b.startTime);
        return byTime != 0 ? byTime : a.subjectName.compareTo(b.subjectName);
      });
    return result;
  }

  /// Bloque más temprano de cada clase en el día de hoy, o `null` si no se pudo
  /// consultar el horario.
  Future<Map<int, ({String start, String end, String? room})>?>
      _todaySlots() async {
    try {
      final data = await _api.get('/schedules/mine');
      final rows = data is Map ? data['schedules'] : null;
      if (rows is! List) return null;
      final todayIndex = DateTime.now().weekday - 1; // 0 = lunes … 6 = domingo
      final slots = <int, ({String start, String end, String? room})>{};
      for (final raw in rows) {
        if (raw is! Map) continue;
        if (raw['kind'] != 'class' || raw['weekdayIndex'] != todayIndex) {
          continue;
        }
        final classId = int.tryParse('${raw['classId']}');
        if (classId == null) continue;
        final start = '${raw['startTime'] ?? ''}';
        final known = slots[classId];
        if (known != null && known.start.compareTo(start) <= 0) continue;
        slots[classId] = (
          start: start,
          end: '${raw['endTime'] ?? ''}',
          room: raw['room'] == null ? null : '${raw['room']}',
        );
      }
      return slots;
    } catch (_) {
      return null;
    }
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
