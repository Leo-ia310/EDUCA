import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/attendance_repository.dart';
import '../../domain/attendance_sync_service.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

const _uuid = Uuid();

/// Estado del pase de asistencia para una clase + fecha concreta.
class AttendanceTakeState {
  const AttendanceTakeState({
    this.loading = false,
    this.error,
    this.classBrief,
    this.date,
    this.rows = const [],
    this.sessionUuid,
    this.finished = false,
  });

  final bool loading;
  final String? error;
  final ClassSessionBrief? classBrief;
  final DateTime? date;
  final List<AttendanceRow> rows;
  final String? sessionUuid;
  final bool finished;

  int get total => rows.length;
  int get present => rows
      .where(
        (r) =>
            r.status == AttendanceStatus.present ||
            r.status == AttendanceStatus.excused ||
            r.status == AttendanceStatus.permission,
      )
      .length;
  int get absent =>
      rows.where((r) => r.status == AttendanceStatus.absent).length;
  int get late => rows.where((r) => r.status == AttendanceStatus.late).length;
  int get pendingSync => rows.where((r) => !r.persisted).length;

  AttendanceTakeState copyWith({
    bool? loading,
    String? error,
    ClassSessionBrief? classBrief,
    DateTime? date,
    List<AttendanceRow>? rows,
    String? sessionUuid,
    bool? finished,
    bool clearError = false,
  }) {
    return AttendanceTakeState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      classBrief: classBrief ?? this.classBrief,
      date: date ?? this.date,
      rows: rows ?? this.rows,
      sessionUuid: sessionUuid ?? this.sessionUuid,
      finished: finished ?? this.finished,
    );
  }
}

class AttendanceRow {
  AttendanceRow({
    required this.student,
    required this.status,
    this.notes,
    this.persisted = false,
    this.conflict = false,
    this.conflictStatus,
    this.conflictNotes,
  });
  final StudentBrief student;
  AttendanceStatus? status;
  bool conflict;
  final AttendanceStatus? conflictStatus;
  final String? conflictNotes;
  String? notes;
  bool persisted;
}

class AttendanceTakeController extends StateNotifier<AttendanceTakeState> {
  AttendanceTakeController({
    required this.repo,
    required this.sync,
    required this.teacherId,
  }) : super(const AttendanceTakeState());

  final AttendanceRepository repo;
  final AttendanceSyncService sync;
  final int teacherId;
  final _markGenerations = <int, int>{};
  int _loadGeneration = 0;

  Future<void> load({
    required ClassSessionBrief brief,
    DateTime? date,
  }) async {
    final generation = ++_loadGeneration;
    final d = date ?? DateTime.now();
    if (!brief.can('attendance.write')) {
      state =
          state.copyWith(error: 'No tienes permiso para registrar asistencia.');
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final roster = await repo.classRoster(classId: brief.classId, date: d);
      final rows = roster.map((r) {
        final existing = r.record;
        return AttendanceRow(
          student: r.student,
          status: existing?.status,
          conflict: existing?.syncState == SyncState.conflict,
          conflictStatus: existing?.conflictStatus,
          conflictNotes: existing?.conflictNotes,
          notes: existing?.notes,
          persisted: existing != null,
        );
      }).toList();
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        loading: false,
        classBrief: brief,
        date: d,
        rows: rows,
        sessionUuid: state.sessionUuid ?? _uuid.v4(),
      );
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> setStatus(int studentId, AttendanceStatus status) async {
    if (!mounted) return false;
    final brief = state.classBrief, date = state.date;
    if (brief == null || date == null) return false;
    final previous =
        state.rows.where((r) => r.student.id == studentId).firstOrNull;
    if (previous == null) return false;
    final generation = (_markGenerations[studentId] ?? 0) + 1;
    _markGenerations[studentId] = generation;
    try {
      await repo.upsertRecord(AttendanceRecord(
          uuid: _uuid.v4(),
          classId: brief.classId,
          studentId: studentId,
          status: status,
          recordedAt: date,
          syncState: SyncState.pendingSync,
          notes: previous.notes,),);
      if (!mounted ||
          _markGenerations[studentId] != generation ||
          state.classBrief?.classId != brief.classId ||
          state.date != date) {
        return false;
      }
      sync.touchPending();
      state = state.copyWith(rows: [
        for (final row in state.rows)
          if (row.student.id == studentId)
            AttendanceRow(
                student: row.student,
                status: status,
                notes: row.notes,
                persisted: true,)
          else
            row,
      ],);
      return true;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
            error:
                'No se pudo guardar la marcación en este dispositivo. $error',);
      }
      return false;
    }
  }

  /// Marca todos los estudiantes como presentes (atajo común).
  Future<void> markAllPresent() async {
    for (final r in state.rows) {
      if (!r.conflict &&
          (r.status != AttendanceStatus.present || !r.persisted)) {
        await setStatus(r.student.id, AttendanceStatus.present);
      }
    }
  }

  Future<void> finishPass() async {
    if (!mounted || state.loading) return;
    final brief = state.classBrief,
        date = state.date,
        sessionUuid = state.sessionUuid;
    if (brief == null || date == null || sessionUuid == null) return;
    if (state.rows.any((r) => r.status == null || r.conflict)) {
      state = state.copyWith(
          error:
              'Revisa los conflictos y marca cada estudiante, o usa Todos presentes.',);
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      for (final row in state.rows.where((r) => !r.persisted)) {
        if (!await setStatus(row.student.id, row.status!)) {
          throw StateError('No se pudo guardar una marcación local.');
        }
      }
      await repo.finishSession(
          sessionUuid: sessionUuid,
          classId: brief.classId,
          date: date,
          teacherId: teacherId,);
      if (!mounted) return;
      sync.touchPending();
      await sync.processQueue();
      if (!mounted) return;
      final conflicts = sync.local
          .recordsForSession(classId: brief.classId, date: date)
          .where((r) => r.syncStateIndex == 2)
          .toList();
      if (conflicts.isNotEmpty) {
        state =
            state.copyWith(loading: false, error: sync.state.lastError, rows: [
          for (final row in state.rows)
            if (conflicts.any((r) => r.studentId == row.student.id))
              AttendanceRow(
                  student: row.student,
                  status: row.status,
                  notes: row.notes,
                  persisted: true,
                  conflict: true,
                  conflictStatus: AttendanceStatus.values
                      .where((s) =>
                          s.id ==
                          conflicts
                              .firstWhere((r) => r.studentId == row.student.id)
                              .conflictStatusId,)
                      .firstOrNull,
                  conflictNotes: conflicts
                      .firstWhere((r) => r.studentId == row.student.id)
                      .conflictNotes,)
            else
              row,
        ],);
        return;
      }
      state = state.copyWith(loading: false, finished: true);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
            loading: false, error: 'No se pudo finalizar el pase. $error',);
      }
    }
  }
}

final attendanceTakeControllerProvider = StateNotifierProvider.autoDispose<
    AttendanceTakeController, AttendanceTakeState>((ref) {
  // The authenticated backend derives the recording teacher; no identity RPC is needed offline.
  const teacherId = 0;
  return AttendanceTakeController(
    repo: ref.watch(attendanceRepositoryProvider),
    sync: ref.watch(attendanceSyncProvider.notifier),
    teacherId: teacherId,
  );
});

final todaysClassesProvider =
    FutureProvider<List<ClassSessionBrief>>((ref) async {
  return ref.watch(attendanceRepositoryProvider).todaysClasses(
        teacherId: 0,
      );
});
