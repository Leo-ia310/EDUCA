import 'package:hive/hive.dart';

import '../models/local_attendance.dart';
import '../models/local_class_session.dart';
import '../models/sync_entry.dart';

/// Acceso CRUD a las cajas Hive de asistencia. NO contiene reglas de negocio
/// — esas viven en el repository.
class AttendanceLocalDataSource {
  AttendanceLocalDataSource({
    required Box<LocalAttendance> records,
    required Box<LocalClassSession> sessions,
    required Box<SyncEntry> queue,
  })  : _records = records,
        _sessions = sessions,
        _queue = queue;

  final Box<LocalAttendance> _records;
  final Box<LocalClassSession> _sessions;
  final Box<SyncEntry> _queue;

  // -------- Attendance records --------
  Future<void> upsertRecord(LocalAttendance r) => _records.put(r.uuid, r);

  LocalAttendance? recordFor({
    required int classId,
    required int studentId,
    required DateTime date,
  }) {
    final dayStart =
        DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd =
        DateTime(date.year, date.month, date.day, 23, 59, 59)
            .millisecondsSinceEpoch;
    for (final r in _records.values) {
      if (r.classId == classId &&
          r.studentId == studentId &&
          r.recordedAtMs >= dayStart &&
          r.recordedAtMs <= dayEnd) {
        return r;
      }
    }
    return null;
  }

  List<LocalAttendance> recordsForSession({
    required int classId,
    required DateTime date,
  }) {
    final dayStart =
        DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd =
        DateTime(date.year, date.month, date.day, 23, 59, 59)
            .millisecondsSinceEpoch;
    return _records.values
        .where((r) =>
            r.classId == classId &&
            r.recordedAtMs >= dayStart &&
            r.recordedAtMs <= dayEnd)
        .toList();
  }

  List<LocalAttendance> allRecords() => _records.values.toList();

  int pendingCount() {
    var count = 0;
    for (final r in _records.values) {
      if (r.syncStateIndex == 0 || r.syncStateIndex == 3) count++;
    }
    return count;
  }

  // -------- Sessions --------
  Future<void> upsertSession(LocalClassSession s) => _sessions.put(s.uuid, s);

  LocalClassSession? sessionByKey({
    required int classId,
    required DateTime date,
  }) {
    final dayStart = DateTime(date.year, date.month, date.day);
    for (final s in _sessions.values) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.dateMs);
      final sd = DateTime(d.year, d.month, d.day);
      if (s.classId == classId && sd == dayStart) return s;
    }
    return null;
  }

  List<LocalClassSession> allSessions() => _sessions.values.toList()
    ..sort((a, b) => b.dateMs.compareTo(a.dateMs));

  // -------- Sync queue --------
  Future<void> enqueue(SyncEntry entry) => _queue.put(entry.id, entry);
  Future<void> removeFromQueue(String id) => _queue.delete(id);
  List<SyncEntry> queuedEntries() => _queue.values.toList()
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
}

