import 'package:uuid/uuid.dart';

import '../../domain/attendance_repository.dart';
import '../../domain/entities.dart';
import '../datasources/attendance_local_datasource.dart';
import '../datasources/attendance_remote_datasource.dart';
import '../mock_attendance_data.dart';
import '../models/local_attendance.dart';
import '../models/local_class_session.dart';
import '../models/sync_entry.dart';

const _uuid = Uuid();

/// Implementación **offline-first** del repositorio de asistencia.
///
/// Reglas:
/// - Todas las escrituras pasan primero por Hive y luego se encolan en
///   `sync_queue`.
/// - El [AttendanceSyncService] procesa la cola cuando hay conectividad.
/// - El roster (catálogo de estudiantes por clase) se sirve desde mocks
///   cuando no hay [AttendanceRemoteDataSource]; en producción se cachea por
///   institución y se refresca en background.
class AttendanceRepositoryImpl implements AttendanceRepository {
  AttendanceRepositoryImpl({
    required this.local,
    this.remote,
    required this.institutionId,
  });

  final AttendanceLocalDataSource local;
  final AttendanceRemoteDataSource? remote;
  final int institutionId;

  @override
  Future<List<ClassSessionBrief>> todaysClasses({required int teacherId}) async {
    // En demo, devolvemos clases mock. En producción, leeríamos de schedules.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return AttendanceMock.todaysClasses;
  }

  @override
  Future<List<({StudentBrief student, AttendanceRecord? record})>> classRoster({
    required int classId,
    required DateTime date,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final students = AttendanceMock.studentsOf(classId);
    return students.map((s) {
      final existing = local.recordFor(
        classId: classId,
        studentId: s.id,
        date: date,
      );
      return (student: s, record: existing?.toEntity());
    }).toList();
  }

  @override
  Future<AttendanceRecord> upsertRecord(AttendanceRecord record) async {
    final existing = local.recordFor(
      classId: record.classId,
      studentId: record.studentId,
      date: record.recordedAt,
    );
    final uuid = existing?.uuid ?? record.uuid;
    final merged = record.copyWith().toMutableUuid(uuid);
    final localModel = LocalAttendance.fromEntity(merged);
    await local.upsertRecord(localModel);

    // Encolar para sincronizar (solo si todavía no está sincronizado).
    if (merged.syncState != SyncState.synced) {
      await local.enqueue(
        SyncEntry(
          id: _uuid.v4(),
          tableName: 'attendances',
          recordUuid: merged.uuid,
          operation: 'UPSERT',
          payload: const {},
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    return merged;
  }

  @override
  Future<void> finishSession({
    required String sessionUuid,
    required int classId,
    required DateTime date,
    required int teacherId,
  }) async {
    final existing = local.sessionByKey(classId: classId, date: date);
    final session = existing ??
        LocalClassSession(
          uuid: sessionUuid,
          classId: classId,
          dateMs: date.millisecondsSinceEpoch,
          teacherId: teacherId,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );
    await local.upsertSession(session);

    // Encolar la sesión.
    await local.enqueue(
      SyncEntry(
        id: _uuid.v4(),
        tableName: 'class_sessions',
        recordUuid: session.uuid,
        operation: 'UPSERT',
        payload: const {},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // Vincular todos los marcados del día con el session uuid local.
    final records = local.recordsForSession(classId: classId, date: date);
    for (final r in records) {
      // No tenemos server id todavía; se reemplazará en sync.
      r.classSessionId = -1;
      r.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
      await local.upsertRecord(r);
    }
  }

  @override
  Future<List<AttendanceSessionSummary>> sessionsHistory({
    int? classId,
    int limit = 50,
  }) async {
    final sessions = local.allSessions();
    final result = <AttendanceSessionSummary>[];
    for (final s in sessions) {
      if (classId != null && s.classId != classId) continue;
      final records = local.recordsForSession(
        classId: s.classId,
        date: s.date,
      );
      var present = 0, absent = 0, late = 0, pending = 0;
      for (final r in records) {
        switch (AttendanceStatus.fromId(r.statusId)) {
          case AttendanceStatus.present:
          case AttendanceStatus.excused:
          case AttendanceStatus.permission:
            present++;
            break;
          case AttendanceStatus.absent:
            absent++;
            break;
          case AttendanceStatus.late:
            late++;
            break;
        }
        if (r.syncStateIndex == SyncState.pendingSync.index ||
            r.syncStateIndex == SyncState.error.index) {
          pending++;
        }
      }
      result.add(AttendanceSessionSummary(
        sessionUuid: s.uuid,
        classId: s.classId,
        subjectName: AttendanceMock.subjectOf(s.classId),
        groupName: AttendanceMock.groupOf(s.classId),
        date: s.date,
        totalStudents: records.length,
        present: present,
        absent: absent,
        late: late,
        pendingSync: pending,
      ));
      if (result.length >= limit) break;
    }
    return result;
  }

  @override
  Future<int> pendingCount() async => local.pendingCount();
}

/// Helper interno para mantener el uuid estable cuando ya hay un registro
/// local para ese (clase, estudiante, día).
extension on AttendanceRecord {
  AttendanceRecord toMutableUuid(String newUuid) {
    if (newUuid == uuid) return this;
    return AttendanceRecord(
      uuid: newUuid,
      classId: classId,
      classSessionId: classSessionId,
      studentId: studentId,
      status: status,
      recordedAt: recordedAt,
      syncState: syncState,
      notes: notes,
    );
  }
}
