import 'package:hive/hive.dart';

/// Cola de sincronización. Cada entrada describe una operación a aplicar en
/// el servidor: cuál tabla, qué uuid de registro y el payload JSON.
class SyncEntry {
  SyncEntry({
    required this.id,
    required this.tableName,
    required this.recordUuid,
    required this.operation,
    required this.payload,
    required this.createdAtMs,
    this.attempts = 0,
    this.lastError,
  });

  String id;
  String tableName;
  String recordUuid;
  String operation; // INSERT / UPDATE / DELETE
  Map<String, dynamic> payload;
  int createdAtMs;
  int attempts;
  String? lastError;
}

class SyncEntryAdapter extends TypeAdapter<SyncEntry> {
  @override
  final int typeId = 3;

  @override
  SyncEntry read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return SyncEntry(
      id: fields[0] as String,
      tableName: fields[1] as String,
      recordUuid: fields[2] as String,
      operation: fields[3] as String,
      payload: Map<String, dynamic>.from(fields[4] as Map),
      createdAtMs: fields[5] as int,
      attempts: fields[6] as int? ?? 0,
      lastError: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncEntry obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.tableName)
      ..writeByte(2)
      ..write(obj.recordUuid)
      ..writeByte(3)
      ..write(obj.operation)
      ..writeByte(4)
      ..write(obj.payload)
      ..writeByte(5)
      ..write(obj.createdAtMs)
      ..writeByte(6)
      ..write(obj.attempts)
      ..writeByte(7)
      ..write(obj.lastError);
  }
}
