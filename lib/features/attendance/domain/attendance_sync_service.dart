import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../data/datasources/attendance_local_datasource.dart';
import '../data/datasources/attendance_remote_datasource.dart';
import '../data/models/local_attendance.dart';
import '../data/models/local_class_session.dart';
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
/// Sigue una estrategia *last-write-wins* basada en `recorded_at`.
class AttendanceSyncService extends StateNotifier<SyncStatus> {
  AttendanceSyncService({
    required this.local,
    required this.remote,
    required this.institutionId,
  }) : super(SyncStatus(pending: local.pendingCount()));

  final AttendanceLocalDataSource local;
  final AttendanceRemoteDataSource? remote;
  final int institutionId;

  bool _running = false;
  Timer? _retryTimer;

  void notifyConnectivity({required bool online}) {
    state = state.copyWith(online: online);
    if (online) {
      // Pequeño debounce para que no dispare durante toggles rápidos.
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 800), processQueue);
    }
  }

  /// Sube todos los registros y sesiones pendientes. Se puede llamar manualmente
  /// (botón "reintentar") o automáticamente al recuperar conexión.
  Future<void> processQueue() async {
    if (_running) return;
    if (remote == null) {
      // Modo demo: simulamos éxito tras un pequeño delay.
      return _processDemo();
    }
    _running = true;
    state = state.copyWith(syncing: true, clearError: true);

    try {
      // 1) Subir sesiones primero (los marcados dependen de ellas).
      for (final s in local.allSessions().where((s) => !s.synced)) {
        final serverId = await remote!.upsertClassSession(
          session: s,
          institutionId: institutionId,
        );
        s.serverId = serverId;
        s.synced = true;
        await local.upsertSession(s);
      }

      // 2) Subir marcados pendientes.
      for (final r in local.allRecords()) {
        if (r.syncStateIndex != 0 && r.syncStateIndex != 3) continue;
        final session = _findSession(r);
        final serverId = await remote!.upsertAttendance(
          record: r,
          institutionId: institutionId,
          classSessionServerId: session?.serverId,
        );
        r.classSessionId = session?.serverId;
        r.syncStateIndex = 1; // synced
        r.serverId = serverId;
        await local.upsertRecord(r);
      }

      state = state.copyWith(
        syncing: false,
        pending: local.pendingCount(),
        lastSyncAt: DateTime.now(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        syncing: false,
        pending: local.pendingCount(),
        lastError: e.toString(),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _processDemo() async {
    _running = true;
    state = state.copyWith(syncing: true, clearError: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (final s in local.allSessions().where((s) => !s.synced)) {
      s.synced = true;
      s.serverId = -1;
      await local.upsertSession(s);
    }
    for (final r in local.allRecords()) {
      if (r.syncStateIndex == 0 || r.syncStateIndex == 3) {
        r.syncStateIndex = 1;
        await local.upsertRecord(r);
      }
    }
    state = state.copyWith(
      syncing: false,
      pending: 0,
      lastSyncAt: DateTime.now(),
    );
    _running = false;
  }

  LocalClassSession? _findSession(LocalAttendance r) {
    final date = DateTime.fromMillisecondsSinceEpoch(r.recordedAtMs);
    return local.sessionByKey(classId: r.classId, date: date);
  }

  /// Llamar tras escribir registros locales para refrescar el contador
  /// "pendientes" en la UI sin esperar a sincronizar.
  void touchPending() {
    state = state.copyWith(pending: local.pendingCount());
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
  );

  // Suscribirse a la conectividad y reflejarla en el estado.
  final sub = ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
    next.whenData((online) => service.notifyConnectivity(online: online));
  });
  ref.onDispose(sub.close);

  return service;
});
