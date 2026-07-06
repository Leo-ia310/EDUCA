import 'dart:convert';

import 'package:hive/hive.dart';

import '../../domain/entities.dart';

/// Modelo Hive para persistir el feed offline. TypeId 4 (los 1/2/3 son de
/// asistencia — ver `hive_init.dart`).
class LocalNotification extends HiveObject {
  LocalNotification({
    required this.id,
    required this.channelCode,
    required this.title,
    required this.body,
    required this.receivedAtMs,
    required this.priorityIndex,
    required this.read,
    this.dataJson,
    this.deepLink,
  });

  String id;
  String channelCode;
  String title;
  String body;
  int receivedAtMs;
  int priorityIndex;
  bool read;
  String? dataJson;
  String? deepLink;

  AppNotification toEntity() => AppNotification(
        id: id,
        channel: NotificationChannel.fromCode(channelCode),
        title: title,
        body: body,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAtMs),
        priority: NotificationPriority.values[priorityIndex],
        read: read,
        data: dataJson == null
            ? const {}
            : Map<String, dynamic>.from(jsonDecode(dataJson!) as Map),
        deepLink: deepLink,
      );

  static LocalNotification fromEntity(AppNotification n) => LocalNotification(
        id: n.id,
        channelCode: n.channel.code,
        title: n.title,
        body: n.body,
        receivedAtMs: n.receivedAt.millisecondsSinceEpoch,
        priorityIndex: n.priority.index,
        read: n.read,
        dataJson: n.data.isEmpty ? null : jsonEncode(n.data),
        deepLink: n.deepLink,
      );
}

/// Adapter manual — SIN codegen. TypeId 4 es exclusivo de notificaciones.
class LocalNotificationAdapter extends TypeAdapter<LocalNotification> {
  @override
  final int typeId = 4;

  @override
  LocalNotification read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return LocalNotification(
      id: fields[0] as String,
      channelCode: fields[1] as String,
      title: fields[2] as String,
      body: fields[3] as String,
      receivedAtMs: fields[4] as int,
      priorityIndex: fields[5] as int,
      read: fields[6] as bool,
      dataJson: fields[7] as String?,
      deepLink: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LocalNotification obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.channelCode)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.body)
      ..writeByte(4)
      ..write(obj.receivedAtMs)
      ..writeByte(5)
      ..write(obj.priorityIndex)
      ..writeByte(6)
      ..write(obj.read)
      ..writeByte(7)
      ..write(obj.dataJson)
      ..writeByte(8)
      ..write(obj.deepLink);
  }
}
