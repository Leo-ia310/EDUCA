import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/attendance/data/models/local_attendance.dart';
import '../../features/attendance/data/models/local_class_session.dart';
import '../../features/attendance/data/models/sync_entry.dart';
import '../../features/notifications/data/models/local_notification.dart';

/// Nombres canónicos de cajas Hive. Usar siempre estas constantes — un typo
/// puede silenciosamente abrir una box vacía.
class HiveBoxes {
  HiveBoxes._();
  static const attendanceRecords = 'attendance_records';
  static const classSessions = 'class_sessions_local';
  static const syncQueue = 'sync_queue';
  static const notifications = 'notifications_feed';
}

class HiveInit {
  HiveInit._();

  static Future<void> init() async {
    await Hive.initFlutter();

    // Adapters manuales — sin codegen.
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(LocalAttendanceAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(LocalClassSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SyncEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(LocalNotificationAdapter());
    }

    await Future.wait([
      Hive.openBox<LocalAttendance>(HiveBoxes.attendanceRecords),
      Hive.openBox<LocalClassSession>(HiveBoxes.classSessions),
      Hive.openBox<SyncEntry>(HiveBoxes.syncQueue),
      Hive.openBox<LocalNotification>(HiveBoxes.notifications),
    ]);
  }
}

final attendanceBoxProvider = Provider<Box<LocalAttendance>>((ref) {
  return Hive.box<LocalAttendance>(HiveBoxes.attendanceRecords);
});

final classSessionBoxProvider = Provider<Box<LocalClassSession>>((ref) {
  return Hive.box<LocalClassSession>(HiveBoxes.classSessions);
});

final syncQueueBoxProvider = Provider<Box<SyncEntry>>((ref) {
  return Hive.box<SyncEntry>(HiveBoxes.syncQueue);
});

final notificationsBoxProvider = Provider<Box<LocalNotification>>((ref) {
  return Hive.box<LocalNotification>(HiveBoxes.notifications);
});
