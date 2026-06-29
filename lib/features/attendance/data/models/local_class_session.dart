import 'package:hive/hive.dart';

/// Sesión de clase generada cuando el docente "finaliza pase". Es el ancla
/// para agrupar los [LocalAttendance] de un mismo pase y subirlos juntos.
class LocalClassSession {
  LocalClassSession({
    required this.uuid,
    required this.classId,
    required this.dateMs,
    required this.teacherId,
    required this.createdAtMs,
    this.serverId,
    this.synced = false,
  });

  String uuid;
  int classId;
  int dateMs;
  int teacherId;
  int createdAtMs;
  int? serverId;
  bool synced;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
}

class LocalClassSessionAdapter extends TypeAdapter<LocalClassSession> {
  @override
  final int typeId = 2;

  @override
  LocalClassSession read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return LocalClassSession(
      uuid: fields[0] as String,
      classId: fields[1] as int,
      dateMs: fields[2] as int,
      teacherId: fields[3] as int,
      createdAtMs: fields[4] as int,
      serverId: fields[5] as int?,
      synced: fields[6] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, LocalClassSession obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.classId)
      ..writeByte(2)
      ..write(obj.dateMs)
      ..writeByte(3)
      ..write(obj.teacherId)
      ..writeByte(4)
      ..write(obj.createdAtMs)
      ..writeByte(5)
      ..write(obj.serverId)
      ..writeByte(6)
      ..write(obj.synced);
  }
}
