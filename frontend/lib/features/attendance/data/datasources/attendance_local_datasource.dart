import 'dart:async';
import 'package:hive/hive.dart';

import '../models/local_attendance.dart';
import '../models/local_class_session.dart';
import '../models/sync_entry.dart';

/// Acceso CRUD a las cajas Hive de asistencia. NO contiene reglas de negocio
/// — esas viven en el repository.
class AttendanceLocalDataSource {
  AttendanceLocalDataSource({
    this.scope = 'demo',
    Box<dynamic>? catalog,
    required Box<LocalAttendance> records,
    required Box<LocalClassSession> sessions,
    required Box<SyncEntry> queue,
  })  : _records = records,
        _sessions = sessions,
        _queue = queue,
        _catalog = catalog {
    _watch = _records.watch().listen((_) => _recordIndex = null);
  }

  StreamSubscription<BoxEvent>? _watch;
  Map<String, List<LocalAttendance>>? _recordIndex;
  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, "0")}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}';
  Map<String, List<LocalAttendance>> get _index {
    if (_recordIndex != null) return _recordIndex!;
    final result = <String, List<LocalAttendance>>{};
    for (final row in _scoped(_records)) {
      final key =
          '${row.classId}/${row.classDate ?? _day(DateTime.fromMillisecondsSinceEpoch(row.recordedAtMs))}';
      (result[key] ??= []).add(row);
    }
    return _recordIndex = result;
  }

  void dispose() {
    unawaited(_watch?.cancel());
    _recordIndex = null;
  }

  final Box<dynamic>? _catalog;
  Future<void> cacheCatalog(
      String name, List<Map<String, dynamic>> rows,) async {
    await _catalog?.put(_key(name),
        {'savedAt': DateTime.now().toUtc().toIso8601String(), 'items': rows},);
  }

  List<Map<String, dynamic>>? cachedCatalog(String name) {
    final value = _catalog?.get(_key(name));
    if (value is! Map || value['items'] is! List) return null;
    return (value['items'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  final String scope;
  String _key(String id) => '$scope/$id';
  List<T> _scoped<T>(Box<T> box) => box
      .toMap()
      .entries
      .where((entry) =>
          entry.key is String && (entry.key as String).startsWith('$scope/'),)
      .map((entry) => entry.value)
      .toList();
  Future<void> removeRecord(String uuid) {
    _recordIndex = null;
    return _records.delete(_key(uuid));
  }

  LocalAttendance? recordByUuid(String uuid) => _records.get(_key(uuid));
  final Box<LocalAttendance> _records;
  final Box<LocalClassSession> _sessions;
  final Box<SyncEntry> _queue;

  // -------- Attendance records --------
  Future<void> upsertRecord(LocalAttendance r) {
    _recordIndex = null;
    return _records.put(_key(r.uuid), r);
  }

  Future<void> upsertRecords(List<LocalAttendance> rows) {
    _recordIndex = null;
    return _records.putAll({for (final row in rows) _key(row.uuid): row});
  }

  LocalAttendance? recordFor({
    required int classId,
    required int studentId,
    required DateTime date,
  }) {
    return _index['$classId/${_day(date)}']
        ?.where((r) => r.studentId == studentId)
        .firstOrNull;
  }

  List<LocalAttendance> recordsForSession(
          {required int classId, required DateTime date,}) =>
      List.unmodifiable(
          _index['$classId/${_day(date)}'] ?? const <LocalAttendance>[],);

  List<LocalAttendance> allRecords() => _scoped(_records).toList();

  int pendingCount() {
    var count = 0;
    for (final r in _scoped(_records)) {
      if (r.syncStateIndex != 1) count++;
    }
    return count + allSessions().where((s) => !s.synced).length;
  }

  // -------- Sessions --------
  Future<void> upsertSession(LocalClassSession s) =>
      _sessions.put(_key(s.uuid), s);

  LocalClassSession? sessionByKey({
    required int classId,
    required DateTime date,
  }) {
    final dayStart = DateTime(date.year, date.month, date.day);
    for (final s in _scoped(_sessions)) {
      final d = s.date;
      final sd = DateTime(d.year, d.month, d.day);
      if (s.classId == classId && sd == dayStart) return s;
    }
    return null;
  }

  List<LocalClassSession> allSessions() =>
      _scoped(_sessions).toList()..sort((a, b) => b.dateMs.compareTo(a.dateMs));

  // -------- Sync queue --------
  SyncEntry? queueById(String id) => _queue.get(_key(id));
  Future<void> enqueue(SyncEntry entry) => _queue.put(_key(entry.id), entry);
  Future<void> removeFromQueue(String id) => _queue.delete(_key(id));
  List<SyncEntry> queuedEntries() => _scoped(_queue).toList()
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
}
