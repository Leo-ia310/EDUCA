import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/notifications/domain/entities.dart';

/// Callback ejecutado cuando el usuario toca una notificación.
typedef NotificationTapCallback = void Function(AppNotification n);

/// Wrapper alrededor de `flutter_local_notifications`. Responsable de:
/// - inicializar canales Android por [NotificationChannel]
/// - mostrar notificaciones heads-up cuando la app está en foreground
/// - enrutar el tap al `NotificationTapCallback` con el payload deserializado
class LocalNotificationsService {
  LocalNotificationsService._();

  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _tapController = StreamController<AppNotification>.broadcast();
  bool _initialized = false;

  Stream<AppNotification> get onTap => _tapController.stream;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onDidTap,
    );

    // Registrar un canal Android por cada categoría — así el usuario puede
    // silenciar por tipo desde los Ajustes del sistema.
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    for (final ch in NotificationChannel.values) {
      await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
        ch.code,
        ch.title,
        description: ch.description,
        importance: _importanceFor(ch),
      ));
    }

    _initialized = true;
  }

  Importance _importanceFor(NotificationChannel ch) => switch (ch) {
        NotificationChannel.message => Importance.high,
        NotificationChannel.task => Importance.high,
        NotificationChannel.grade => Importance.defaultImportance,
        NotificationChannel.attendance => Importance.high,
        NotificationChannel.announcement => Importance.defaultImportance,
        NotificationChannel.payment => Importance.defaultImportance,
        NotificationChannel.system => Importance.low,
      };

  Priority _priorityFor(NotificationPriority p) => switch (p) {
        NotificationPriority.low => Priority.low,
        NotificationPriority.normal => Priority.defaultPriority,
        NotificationPriority.high => Priority.high,
        NotificationPriority.urgent => Priority.max,
      };

  Future<void> show(AppNotification n) async {
    if (!_initialized) await init();
    await _plugin.show(
      n.id.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          n.channel.code,
          n.channel.title,
          channelDescription: n.channel.description,
          importance: _importanceFor(n.channel),
          priority: _priorityFor(n.priority),
          styleInformation: BigTextStyleInformation(n.body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({
        'id': n.id,
        'channel': n.channel.code,
        'title': n.title,
        'body': n.body,
        'deepLink': n.deepLink,
        'data': n.data,
        'receivedAt': n.receivedAt.toIso8601String(),
        'priority': n.priority.index,
      }),
    );
  }

  Future<void> cancel(String id) => _plugin.cancel(id.hashCode);
  Future<void> cancelAll() => _plugin.cancelAll();

  void _onDidTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final n = AppNotification(
        id: map['id'] as String,
        channel: NotificationChannel.fromCode(map['channel'] as String?),
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        deepLink: map['deepLink'] as String?,
        data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
        receivedAt: DateTime.tryParse(map['receivedAt'] as String? ?? '') ??
            DateTime.now(),
        priority: NotificationPriority
            .values[(map['priority'] as int?) ?? 1],
        read: false,
      );
      _tapController.add(n);
    } catch (_) {
      // Payload inválido — ignoramos silenciosamente.
    }
  }

  /// Solicita permiso explícito en iOS/Android 13+.
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission();
      return ok ?? true;
    }
    return true;
  }
}
