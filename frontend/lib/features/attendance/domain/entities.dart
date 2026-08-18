import 'package:equatable/equatable.dart';

/// Estado del marcado de asistencia. El `id` coincide con
/// `catalog_attendance_statuses.id` en Supabase.
enum AttendanceStatus {
  present(1, 'Presente', 'PRE'),
  absent(2, 'Ausente', 'AUS'),
  late(3, 'Tarde', 'TAR'),
  excused(4, 'Justificado', 'JUS'),
  permission(5, 'Permiso', 'PER');

  const AttendanceStatus(this.id, this.label, this.code);
  final int id;
  final String label;
  final String code;

  static AttendanceStatus fromId(int id) =>
      AttendanceStatus.values.firstWhere(
        (e) => e.id == id,
        orElse: () => AttendanceStatus.present,
      );
}

/// Estado del registro respecto al backend.
enum SyncState {
  /// Todavía no se ha subido al servidor.
  pendingSync,

  /// Subido correctamente.
  synced,

  /// Hubo un conflicto (el server tiene un registro más reciente).
  conflict,

  /// Falló y se reintentará.
  error,
}

/// Resumen de una clase del día sobre la cual el maestro puede tomar
/// asistencia.
class ClassSessionBrief extends Equatable {
  const ClassSessionBrief({
    required this.classId,
    required this.groupId,
    required this.subjectName,
    required this.groupName,
    required this.startTime,
    required this.endTime,
    required this.studentCount,
    this.classroom,
  });

  final int classId;
  final int groupId;
  final String subjectName;
  final String groupName;
  final String startTime;
  final String endTime;
  final int studentCount;
  final String? classroom;

  @override
  List<Object?> get props => [classId, groupId, subjectName, startTime];
}

/// Estudiante listo para pasar lista.
class StudentBrief extends Equatable {
  const StudentBrief({
    required this.id,
    required this.fullName,
    this.studentCode,
    this.avatarUrl,
  });

  final int id;
  final String fullName;
  final String? studentCode;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, fullName];
}

/// Entidad de dominio de un marcado de asistencia.
class AttendanceRecord extends Equatable {
  const AttendanceRecord({
    required this.uuid,
    required this.classId,
    required this.studentId,
    required this.status,
    required this.recordedAt,
    required this.syncState,
    this.notes,
    this.classSessionId,
  });

  final String uuid;
  final int classId;
  final int? classSessionId;
  final int studentId;
  final AttendanceStatus status;
  final DateTime recordedAt;
  final String? notes;
  final SyncState syncState;

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    DateTime? recordedAt,
    String? notes,
    SyncState? syncState,
    int? classSessionId,
  }) {
    return AttendanceRecord(
      uuid: uuid,
      classId: classId,
      classSessionId: classSessionId ?? this.classSessionId,
      studentId: studentId,
      status: status ?? this.status,
      recordedAt: recordedAt ?? this.recordedAt,
      notes: notes ?? this.notes,
      syncState: syncState ?? this.syncState,
    );
  }

  @override
  List<Object?> get props => [uuid, status, syncState, recordedAt];
}

/// Resumen de un pase de asistencia (una sesión + sus marcados).
class AttendanceSessionSummary extends Equatable {
  const AttendanceSessionSummary({
    required this.sessionUuid,
    required this.classId,
    required this.subjectName,
    required this.groupName,
    required this.date,
    required this.totalStudents,
    required this.present,
    required this.absent,
    required this.late,
    required this.pendingSync,
  });

  final String sessionUuid;
  final int classId;
  final String subjectName;
  final String groupName;
  final DateTime date;
  final int totalStudents;
  final int present;
  final int absent;
  final int late;
  final int pendingSync;

  @override
  List<Object?> get props => [sessionUuid, date];
}
