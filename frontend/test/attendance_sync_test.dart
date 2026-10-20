import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/attendance/data/datasources/attendance_local_datasource.dart';
import 'package:educa360/features/attendance/data/datasources/attendance_remote_datasource.dart';
import 'package:educa360/features/attendance/data/models/local_attendance.dart';
import 'package:educa360/features/attendance/data/models/local_class_session.dart';
import 'package:educa360/features/attendance/data/models/sync_entry.dart';
import 'package:educa360/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:educa360/features/attendance/domain/attendance_sync_service.dart';
import 'package:educa360/features/attendance/domain/entities.dart';
import 'package:educa360/features/attendance/presentation/controllers/attendance_take_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class Api implements BackendApiClient {
  final requests = <Map<String, dynamic>>[];
  final receipts = <String, Map<String, dynamic>>{};
  final versions = <String, int>{};
  bool loseResponse = false, conflict = false;
  BackendApiException? readError;
  Map<String, dynamic> rosterRow = {
    'studentId': '1',
    'name': 'Estudiante',
    'statusId': null,
    'notes': '',
  };
  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    if (readError != null) throw readError!;
    return {
      'sessionId': '101',
      'students': [rosterRow],
    };
  }

  @override
  Future<dynamic> call(String action,
      [Map<String, dynamic> payload = const {},]) async {
    if (readError != null) throw readError!;
    return [
      {
        'classId': 1,
        'groupId': 1,
        'subjectName': 'Clase real',
        'groupName': 'Grupo real',
        'startTime': '08:00',
        'endTime': '09:00',
        'studentCount': 1,
        'permissions': ['attendance.write'],
      }
    ];
  }

  Completer<void>? gate;
  @override
  Future<dynamic> post(String path,
      {Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    final request =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
    requests.add(request);
    final marks = request['marks'] as List;
    final sessions = <String, Map<String, dynamic>>{};
    for (final row in [...request['sessions'] as List, ...marks]) {
      sessions['${row['classId']}/${row['date']}'] = {
        'classId': row['classId'].toString(),
        'date': row['date'],
        'id': '101',
      };
    }
    final replies = <Map<String, dynamic>>[];
    for (final mark in marks) {
      final id = mark['operationId'] as String,
          key = mark['studentId'].toString();
      final existing = receipts[id];
      if (existing != null) {
        replies.add(existing);
        continue;
      }
      final version = (versions[key] ?? 0) + 1;
      versions[key] = version;
      final reply = {
        'operationId': id,
        'uuid': mark['uuid'],
        'id': key,
        'classSessionId': '101',
        'version': version,
        'status': conflict ? 'conflict' : 'applied',
        if (conflict) 'statusId': 2,
        if (conflict) 'notes': 'Servidor',
      };
      receipts[id] = reply;
      replies.add(reply);
    }
    if (gate != null) await gate!.future;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('respuesta perdida');
    }
    return {'sessions': sessions.values.toList(), 'records': replies};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late Box<LocalAttendance> records;
  late Box<LocalClassSession> sessions;
  late Box<SyncEntry> queue;
  late Box<dynamic> catalog;
  late AttendanceLocalDataSource local;
  late Api api;
  late AttendanceSyncService sync;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('educa-attendance-test-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(LocalAttendanceAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(LocalClassSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SyncEntryAdapter());
    records = await Hive.openBox<LocalAttendance>('records');
    sessions = await Hive.openBox<LocalClassSession>('sessions');
    queue = await Hive.openBox<SyncEntry>('queue');
    catalog = await Hive.openBox<dynamic>('catalog');
    local = AttendanceLocalDataSource(
        records: records,
        sessions: sessions,
        queue: queue,
        catalog: catalog,
        scope: '1:teacher',);
    api = Api();
    sync = AttendanceSyncService(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
  });
  tearDown(() async {
    if (sync.mounted) sync.dispose();
    local.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<LocalAttendance> pending([int student = 1]) async {
    final record = LocalAttendance(
        uuid: const Uuid().v4(),
        operationId: const Uuid().v4(),
        classId: 1,
        studentId: student,
        statusId: 1,
        recordedAtMs: DateTime(2026, 10, 18, 12).millisecondsSinceEpoch,
        syncStateIndex: 0,);
    await local.upsertRecord(record);
    await local.enqueue(SyncEntry(
        id: const Uuid().v4(),
        tableName: 'attendances',
        recordUuid: record.uuid,
        operation: 'upsert',
        payload: {'operationId': record.operationId},
        createdAtMs: record.recordedAtMs,),);
    return record;
  }

  test(
      'a lost response retains the queue and reuses the persisted operation after service restart',
      () async {
    final record = await pending();
    api.loseResponse = true;
    await sync.processQueue();
    expect(local.queuedEntries().length, 1);
    expect(local.recordByUuid(record.uuid)!.syncStateIndex, 0);
    sync.dispose();local.dispose();
    await Hive.close();
    records=await Hive.openBox<LocalAttendance>('records');
    sessions=await Hive.openBox<LocalClassSession>('sessions');
    queue=await Hive.openBox<SyncEntry>('queue');catalog=await Hive.openBox<dynamic>('catalog');
    local=AttendanceLocalDataSource(records:records,sessions:sessions,queue:queue,catalog:catalog,scope:'1:teacher');
    sync = AttendanceSyncService(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
    await sync.processQueue();
    expect(api.requests[0], api.requests[1]);
    expect(api.receipts.length, 1);
    expect(local.recordByUuid(record.uuid)!.serverVersion, 1);
    expect(local.recordByUuid(record.uuid)!.syncStateIndex, 1);
    expect(local.queuedEntries(), isEmpty);
  });
  test(
      '205 pending records use three bounded requests and no per-row telemetry requests',
      () async {
    for (var i = 1; i <= 205; i++) {
      await pending(i);
    }
    await sync.processQueue();
    expect(api.requests.map((r) => (r['marks'] as List).length), [100, 100, 5]);
    expect(local.pendingCount(), 0);
    expect(local.queuedEntries(), isEmpty);
  });
  test(
      'an edit during upload remains pending with the acknowledged base version',
      () async {
    final record = await pending();
    api.gate = Completer<void>();
    final operation = sync.processQueue();
    await Future<void>.delayed(Duration.zero);
    final repo = AttendanceRepositoryImpl(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
    await repo.upsertRecord(record.toEntity().copyWith(
        status: AttendanceStatus.late, syncState: SyncState.pendingSync,),);
    api.gate!.complete();
    await operation;
    expect(api.requests.length, 2);
    final second = (api.requests[1]['marks'] as List).single;
    expect(second['expectedVersion'], 1);
    expect(second['statusId'], 3);
    expect(local.recordByUuid(record.uuid)!.serverVersion, 2);
    expect(local.pendingCount(), 0);
  });
  test(
      'conflicts retain the local choice and remote evidence without automatic overwrite',
      () async {
    final record = await pending();
    api.conflict = true;
    await sync.processQueue();
    await sync.processQueue();
    final saved = local.recordByUuid(record.uuid)!;
    expect(api.requests.length, 1);
    expect(saved.syncStateIndex, 2);
    expect(saved.statusId, 1);
    expect(saved.conflictStatusId, 2);
    expect(saved.conflictNotes, 'Servidor');
    expect(local.queuedEntries().length, 1);
    expect(sync.state.lastError, contains('otra sesión'));
  });
  test(
      'account scopes hide other users and preserve unattributed legacy rows without uploading them',
      () async {
    final record = await pending();
    await records.put(
        'legacy-unattributed',
        LocalAttendance(
            uuid: const Uuid().v4(),
            classId: 1,
            studentId: 99,
            statusId: 1,
            recordedAtMs: 0,
            syncStateIndex: 0,),);
    final other = AttendanceLocalDataSource(
        records: records, sessions: sessions, queue: queue, scope: '1:other',);
    expect(other.allRecords(), isEmpty);
    expect(other.queuedEntries(), isEmpty);
    expect(local.allRecords().single.uuid, record.uuid);
    await sync.processQueue();
    expect((api.requests.single['marks'] as List).length, 1);
    expect(records.containsKey('legacy-unattributed'), isTrue);
  });
  test(
      'cached class and roster snapshots work after transport failure but never bypass a forbidden response',
      () async {
    final repo = AttendanceRepositoryImpl(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
    expect((await repo.todaysClasses(teacherId: 0)).single.subjectName,
        'Clase real',);
    await repo.classRoster(classId: 1, date: DateTime(2026, 10, 18));
    api.readError = BackendApiException('sin conexión', retryable: true);
    expect((await repo.todaysClasses(teacherId: 0)).single.classId, 1);
    expect(
        (await repo.classRoster(classId: 1, date: DateTime(2026, 10, 18)))
            .single
            .student
            .fullName,
        'Estudiante',);
    api.readError = BackendApiException('prohibido', statusCode: 403);
    await expectLater(
        repo.classRoster(classId: 1, date: DateTime(2026, 10, 18)),
        throwsA(isA<BackendApiException>()),);
    final other = AttendanceLocalDataSource(
        records: records,
        sessions: sessions,
        queue: queue,
        catalog: catalog,
        scope: '2:other',);
    expect(other.cachedCatalog('classes'), isNull);
    other.dispose();
  });
  test(
      'roster hydration updates a synced local UUID instead of duplicating the same student and day',
      () async {
    final record = await pending();
    await sync.processQueue();
    api.rosterRow = {
      'studentId': '1',
      'name': 'Estudiante',
      'statusId': '3',
      'notes': 'Nueva marca',
      'uuid': const Uuid().v4(),
      'attendanceId': '1',
      'version': 2,
    };
    final repo = AttendanceRepositoryImpl(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
    final roster =
        await repo.classRoster(classId: 1, date: DateTime(2026, 10, 18));
    expect(local.allRecords().length, 1);
    expect(roster.single.record!.uuid, record.uuid);
    expect(local.recordByUuid(record.uuid)!.serverVersion, 2);
    expect(roster.single.record!.status, AttendanceStatus.late);
  });
  test(
      'unmarked students are not counted present; finishing requires an explicit selection',
      () async {
    final repo = AttendanceRepositoryImpl(
        local: local,
        remote: AttendanceRemoteDataSource(api),
        institutionId: 1,);
    final controller =
        AttendanceTakeController(repo: repo, sync: sync, teacherId: 0);
    await controller.load(
        brief: (await repo.todaysClasses(teacherId: 0)).single,
        date: DateTime(2026, 10, 18),);
    expect(controller.state.present, 0);
    expect(controller.state.rows.single.status, isNull);
    await controller.finishPass();
    expect(controller.state.finished, isFalse);
    expect(api.requests, isEmpty);
    await controller.markAllPresent();
    expect(controller.state.present, 1);
    await controller.finishPass();
    expect(controller.state.finished, isTrue);
    expect(local.pendingCount(), 0);
    controller.dispose();
  });
  test(
      'disposal during upload leaves durable local work for the original account',
      () async {
    final record = await pending();
    api.gate = Completer<void>();
    final operation = sync.processQueue();
    await Future<void>.delayed(Duration.zero);
    sync.dispose();
    api.gate!.complete();
    await operation;
    expect(local.recordByUuid(record.uuid)!.syncStateIndex, 0);
    expect(local.queuedEntries().length, 1);
  });
}
