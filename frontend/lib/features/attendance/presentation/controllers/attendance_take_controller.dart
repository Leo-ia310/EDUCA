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
      .where((r) =>
          r.status == AttendanceStatus.present ||
          r.status == AttendanceStatus.excused ||
          r.status == AttendanceStatus.permission)
      .length;
  int get absent =>
      rows.where((r) => r.status == AttendanceStatus.absent).length;
  int get late =>
      rows.where((r) => r.status == AttendanceStatus.late).length;
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
  });
  final StudentBrief student;
  AttendanceStatus status;
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

  Future<void> load({
    required ClassSessionBrief brief,
    DateTime? date,
  }) async {
    final d = date ?? DateTime.now();
    state = state.copyWith(loading: true, clearError: true);
    try {
      final roster = await repo.classRoster(classId: brief.classId, date: d);
      final rows = roster.map((r) {
        final existing = r.record;
        return AttendanceRow(
          student: r.student,
          status: existing?.status ?? AttendanceStatus.present,
          notes: existing?.notes,
          persisted: existing != null,
        );
      }).toList();
      state = state.copyWith(
        loading: false,
        classBrief: brief,
        date: d,
        rows: rows,
        sessionUuid: state.sessionUuid ?? _uuid.v4(),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> setStatus(int studentId, AttendanceStatus status) async {
    final brief = state.classBrief;
    final date = state.date;
    if (brief == null || date == null) return;
    final rows = [...state.rows];
    final idx = rows.indexWhere((r) => r.student.id == studentId);
    if (idx == -1) return;
    rows[idx].status = status;
    state = state.copyWith(rows: rows);

    final record = AttendanceRecord(
      uuid: _uuid.v4(),
      classId: brief.classId,
      studentId: studentId,
      status: status,
      recordedAt: date,
      syncState: SyncState.pendingSync,
      notes: rows[idx].notes,
    );
    await repo.upsertRecord(record);
    rows[idx].persisted = true;
    sync.touchPending();
    state = state.copyWith(rows: rows);
  }

  /// Marca todos los estudiantes como presentes (atajo común).
  Future<void> markAllPresent() async {
    for (final r in state.rows) {
      if (r.status != AttendanceStatus.present) {
        await setStatus(r.student.id, AttendanceStatus.present);
      }
    }
  }

  Future<void> finishPass() async {
    final brief = state.classBrief;
    final date = state.date;
    final sessionUuid = state.sessionUuid;
    if (brief == null || date == null || sessionUuid == null) return;
    state = state.copyWith(loading: true);

    // Asegurarnos de que TODOS los estudiantes tienen un marcado (por defecto
    // presente para evitar olvidos).
    for (final row in state.rows.where((r) => !r.persisted)) {
      await setStatus(row.student.id, row.status);
    }

    await repo.finishSession(
      sessionUuid: sessionUuid,
      classId: brief.classId,
      date: date,
      teacherId: teacherId,
    );
    sync.touchPending();
    // Disparar sync inmediatamente si hay conexión.
    await sync.processQueue();

    state = state.copyWith(loading: false, finished: true);
  }
}

final attendanceTakeControllerProvider = StateNotifierProvider.autoDispose<
    AttendanceTakeController, AttendanceTakeState>((ref) {
  return AttendanceTakeController(
    repo: ref.watch(attendanceRepositoryProvider),
    sync: ref.watch(attendanceSyncProvider.notifier),
    teacherId: 0, // En producción: id real del docente actual.
  );
});

final todaysClassesProvider = FutureProvider<List<ClassSessionBrief>>((ref) {
  return ref.watch(attendanceRepositoryProvider).todaysClasses(teacherId: 0);
});
