import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/env.dart';

import '../../../core/network/connectivity_service.dart';
import '../data/datasources/attendance_local_datasource.dart';
import '../data/datasources/attendance_remote_datasource.dart';
import '../providers.dart';

/// Estado del proceso de sincronización para mostrar en la UI.
@immutable
class SyncStatus {
  const SyncStatus({
    this.online = false,
    this.syncing = false,
    this.pending = 0,
    this.lastSyncAt,
    this.lastError,
  });

  final bool online;
  final bool syncing;
  final int pending;
  final DateTime? lastSyncAt;
  final String? lastError;

  SyncStatus copyWith({
    bool? online,
    bool? syncing,
    int? pending,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncStatus(
      online: online ?? this.online,
      syncing: syncing ?? this.syncing,
      pending: pending ?? this.pending,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Procesa la cola de Hive y la sube a Supabase cuando hay conectividad.
/// Confirma lotes idempotentes y detecta conflictos mediante versión del servidor.
class AttendanceSyncService extends StateNotifier<SyncStatus> {
  AttendanceSyncService({
    required this.local,
    required this.remote,
    required this.institutionId,
    this.demo = false,
  }) : super(SyncStatus(pending: local.pendingCount()));

  final AttendanceLocalDataSource local;
  final AttendanceRemoteDataSource? remote;
  final int institutionId;
  final bool demo;

  Future<void>? _pending;
  Timer? _retryTimer;

  void notifyConnectivity({required bool online}) {
    if (!mounted) return;
    state = state.copyWith(online: online);
    _retryTimer?.cancel();
    if (online) {
      _retryTimer = Timer(
          const Duration(milliseconds: 800), () => unawaited(processQueue()),);
    }
  }

  Future<void> processQueue() {
    if (!mounted) return Future.value();
    if (_pending != null) return _pending!;
    final pending = _process();
    _pending = pending;
    return pending.whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
  }

  Future<void> _process() async {
    if (remote == null && !demo) return;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      await _cleanupAcknowledgedQueue();
      while (mounted) {
        final pendingRecords = local
            .allRecords()
            .where((r) => r.syncStateIndex == 0 || r.syncStateIndex == 3)
            .take(100)
            .toList();
        final pendingSessions =
            local.allSessions().where((s) => !s.synced).take(100).toList();
        if (pendingRecords.isEmpty && pendingSessions.isEmpty) break;
        if (demo) {
          for (final record in pendingRecords) {
            record.syncStateIndex = 1;
            await local.upsertRecord(record);
          }
          for (final session in pendingSessions) {
            session.synced = true;
            session.serverId = -1;
            await local.upsertSession(session);
          }
          for (final entry in local.queuedEntries()) {
            await local.removeFromQueue(entry.id);
          }
          continue;
        }
        // The key is persisted before sending; restart and lost-response retries
        // reuse precisely the same operation. Hive rows are not marked synced yet.
        final marks = <Map<String, dynamic>>[];
        for (final record in pendingRecords) {
          if (record.operationId == null) {
            record.operationId = const Uuid().v4();
            await local.upsertRecord(record);
          }
          marks.add({
            'operationId': record.operationId,
            'uuid': record.uuid,
            'classId': record.classId,
            'date': record.classDate ??
                AttendanceRemoteDataSource.dayKey(
                    DateTime.fromMillisecondsSinceEpoch(record.recordedAtMs),),
            'studentId': record.studentId,
            'statusId': record.statusId,
            'expectedVersion': record.serverVersion,
            'recordedAt':
                DateTime.fromMillisecondsSinceEpoch(record.recordedAtMs)
                    .toUtc()
                    .toIso8601String(),
            'notes': record.notes,
          });
        }
        final sessions = [
          for (final session in pendingSessions)
            {
              'classId': session.classId,
              'date': AttendanceRemoteDataSource.dayKey(session.date),
            },
        ];
        final queued = local.queuedEntries();
        if (!mounted) return;
        final response =
            await remote!.uploadBatch(sessions: sessions, marks: marks);
        if (!mounted) return;
        final replies = (response['records'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        final sessionReplies = (response['sessions'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        final byOperation = {
          for (final row in replies) row['operationId']: row,
        };
        if (byOperation.length != marks.length ||
            replies.length != marks.length ||
            marks.any((m) => !byOperation.containsKey(m['operationId']))) {
          throw StateError('El servidor no confirmó todas las marcaciones.');
        }
        // Validate the complete response before acknowledging any local row.
        for (final row in replies) {
          if (!['applied', 'conflict'].contains(row['status']) ||
              row['version'] is! num ||
              (row['version'] as num) < 0 ||
              int.tryParse(row['classSessionId'].toString()) == null ||
              (row['status'] == 'applied' &&
                  int.tryParse(row['id'].toString()) == null)) {
            throw StateError('Confirmación de asistencia inválida.');
          }
        }
        for (final session in pendingSessions) {
          if (!sessionReplies.any((r) =>
              r['classId'].toString() == session.classId.toString() &&
              r['date'] == AttendanceRemoteDataSource.dayKey(session.date) &&
              int.tryParse(r['id'].toString()) != null,)) {
            throw StateError('El servidor no confirmó todas las sesiones.');
          }
        }
        for (final sent in marks) {
          if (!mounted) return;
          final row = byOperation[sent['operationId']]!;
          final current = local.recordByUuid(sent['uuid'] as String);
          if (current == null) continue;
          final same = current.operationId == sent['operationId'];
          current.serverId = int.tryParse(row['id'].toString());
          current.classSessionId = int.parse(row['classSessionId'].toString());
          current.serverVersion = (row['version'] as num).toInt();
          if (row['status'] == 'conflict') {
            current.syncStateIndex = 2;
            current.conflictStatusId = (row['statusId'] as num?)?.toInt();
            current.conflictNotes = row['notes'] as String?;
          } else if (same) {
            current.syncStateIndex = 1;
            current.conflictStatusId = null;
            current.conflictNotes = null;
          }
          await local.upsertRecord(current);
          if (row['status'] == 'applied') {
            for (final entry in queued.where((e) =>
                e.tableName == 'attendances' && e.recordUuid == sent['uuid'],)) {
              final live = local.queueById(entry.id);
              if (live != null &&
                  (live.payload['operationId'] == sent['operationId'] ||
                      live.payload['operationId'] == null && same)) {
                await local.removeFromQueue(entry.id);
              }
            }
          }
        }
        for (final session in pendingSessions) {
          if (!mounted) return;
          final row = sessionReplies.firstWhere((r) =>
              r['classId'].toString() == session.classId.toString() &&
              r['date'] == AttendanceRemoteDataSource.dayKey(session.date),);
          session.serverId = int.parse(row['id'].toString());
          session.synced = true;
          await local.upsertSession(session);
          for (final entry in queued.where((e) =>
              e.tableName == 'class_sessions' &&
              e.recordUuid == session.uuid,)) {
            await local.removeFromQueue(entry.id);
          }
        }
        // A newer edit made during upload remains pending and gets the acknowledged
        // base version on the next bounded batch. Conflicts never auto-resend.
      }
      if (!mounted) return;
      final conflicts =
          local.allRecords().where((r) => r.syncStateIndex == 2).length;
      state = state.copyWith(
          syncing: false,
          pending: local.pendingCount(),
          lastSyncAt: DateTime.now(),
          clearError: conflicts == 0,
          lastError: conflicts == 0
              ? null
              : 'Hay $conflicts marcaciones modificadas en otra sesión. Revisa el estado del servidor antes de elegir un nuevo valor.',);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
            syncing: false,
            pending: local.pendingCount(),
            lastError: error.toString(),);
      }
    }
  }

  Future<void> _cleanupAcknowledgedQueue() async {
    for (final entry in local.queuedEntries()) {
      if (!mounted) return;
      if (entry.tableName == 'attendances') {
        final row = local.recordByUuid(entry.recordUuid);
        if (row?.syncStateIndex == 1 &&
            row!.serverVersion > 0 &&
            (entry.payload['operationId'] == null ||
                entry.payload['operationId'] == row.operationId)) {
          await local.removeFromQueue(entry.id);
        }
      } else if (entry.tableName == 'class_sessions') {
        final row = local
            .allSessions()
            .where((s) => s.uuid == entry.recordUuid)
            .firstOrNull;
        if (row != null && row.synced && (row.serverId ?? 0) > 0) {
          await local.removeFromQueue(entry.id);
        }
      }
    }
  }

  /// Llamar tras escribir registros locales para refrescar el contador
  /// "pendientes" en la UI sin esperar a sincronizar.
  void touchPending() {
    if (mounted) state = state.copyWith(pending: local.pendingCount());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

final attendanceSyncProvider =
    StateNotifierProvider<AttendanceSyncService, SyncStatus>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  // Cargamos las dependencias de los datasources individualmente.
  final local = ref.watch(attendanceLocalDataSourceProvider);
  final remote = ref.watch(attendanceRemoteDataSourceProvider);
  final institutionId = (repo as dynamic).institutionId as int;

  final service = AttendanceSyncService(
    local: local,
    remote: remote,
    institutionId: institutionId,
    demo: Env.isDemoMode,
  );

  // Suscribirse a la conectividad y reflejarla en el estado.
  final sub = ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
    next.whenData((online) => service.notifyConnectivity(online: online));
  });
  ref.onDispose(sub.close);

  return service;
});
