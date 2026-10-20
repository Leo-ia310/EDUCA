import 'package:hive/hive.dart';

import '../../domain/entities.dart';

/// Registro de asistencia almacenado en Hive. Es la fuente de verdad cuando
/// el dispositivo está offline. Cada registro se identifica de forma estable
/// por su `uuid` (generado en el cliente) — el `serverId` se rellena cuando
/// Supabase devuelve la fila persistida.
class LocalAttendance {
  LocalAttendance({
    required this.uuid,
    required this.classId,
    required this.studentId,
    required this.statusId,
    required this.recordedAtMs,
    required this.syncStateIndex,
    this.notes,
    this.classSessionId,
    this.serverId,
    this.updatedAtMs,
    this.serverVersion = 0,
    this.operationId,
    this.conflictStatusId,
    this.conflictNotes,
    this.classDate,
  });

  String uuid;
  int classId;
  int? classSessionId;
  int studentId;
  int statusId;
  int recordedAtMs;
  int? updatedAtMs;
  String? notes;
  int syncStateIndex;
  int? serverId;
  int serverVersion;
  String? operationId;
  int? conflictStatusId;
  String? conflictNotes;
  String? classDate;

  AttendanceRecord toEntity() => AttendanceRecord(
        uuid: uuid,
        classId: classId,
        classSessionId: classSessionId,
        studentId: studentId,
        status: AttendanceStatus.fromId(statusId),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(recordedAtMs),
        notes: notes,
        conflictStatus: conflictStatusId == null
            ? null
            : AttendanceStatus.fromId(conflictStatusId!),
        conflictNotes: conflictNotes,
        syncState: SyncState.values[syncStateIndex],
      );

  static LocalAttendance fromEntity(AttendanceRecord r) => LocalAttendance(
        uuid: r.uuid,
        classId: r.classId,
        classSessionId: r.classSessionId,
        studentId: r.studentId,
        statusId: r.status.id,
        recordedAtMs: r.recordedAt.millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        classDate:
            '${r.recordedAt.year.toString().padLeft(4, "0")}-${r.recordedAt.month.toString().padLeft(2, "0")}-${r.recordedAt.day.toString().padLeft(2, "0")}',
        notes: r.notes,
        syncStateIndex: r.syncState.index,
      );
}

/// Adapter manual (sin build_runner) para [LocalAttendance].
class LocalAttendanceAdapter extends TypeAdapter<LocalAttendance> {
  @override
  final int typeId = 1;

  @override
  LocalAttendance read(BinaryReader reader) {
    final fieldsCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldsCount; i++) reader.readByte(): reader.read(),
    };
    return LocalAttendance(
      uuid: fields[0] as String,
      classId: fields[1] as int,
      classSessionId: fields[2] as int?,
      studentId: fields[3] as int,
      statusId: fields[4] as int,
      recordedAtMs: fields[5] as int,
      updatedAtMs: fields[6] as int?,
      notes: fields[7] as String?,
      syncStateIndex: fields[8] as int,
      serverId: fields[9] as int?,
      serverVersion: fields[10] as int? ?? 0,
      operationId: fields[11] as String?,
      conflictStatusId: fields[12] as int?,
      conflictNotes: fields[13] as String?,
      classDate: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalAttendance obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.classId)
      ..writeByte(2)
      ..write(obj.classSessionId)
      ..writeByte(3)
      ..write(obj.studentId)
      ..writeByte(4)
      ..write(obj.statusId)
      ..writeByte(5)
      ..write(obj.recordedAtMs)
      ..writeByte(6)
      ..write(obj.updatedAtMs)
      ..writeByte(7)
      ..write(obj.notes)
      ..writeByte(8)
      ..write(obj.syncStateIndex)
      ..writeByte(9)
      ..write(obj.serverId)
      ..writeByte(10)
      ..write(obj.serverVersion)
      ..writeByte(11)
      ..write(obj.operationId)
      ..writeByte(12)
      ..write(obj.conflictStatusId)
      ..writeByte(13)
      ..write(obj.conflictNotes)
      ..writeByte(14)
      ..write(obj.classDate);
  }
}
