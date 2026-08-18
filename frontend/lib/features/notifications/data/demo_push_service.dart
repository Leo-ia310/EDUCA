import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../domain/entities.dart';
import '../domain/push_service.dart';

const _uuid = Uuid();

/// Implementación de demo. NO usa FCM. Sirve para:
/// - correr la app sin `google-services.json` / `GoogleService-Info.plist`
/// - permitir probar el flujo completo (banner heads-up + feed + deep-link)
///   con el botón "Simular notificación" que agrego a la pantalla de
///   alertas.
class DemoPushService implements PushService {
  final _incomingCtrl = StreamController<AppNotification>.broadcast();
  final _tapCtrl = StreamController<AppNotification>.broadcast();
  final _rand = Random();

  static const _samples = <_Sample>[
    _Sample(
      channel: NotificationChannel.message,
      title: 'Nuevo mensaje',
      body: 'Prof. Elena Ramírez te envió un mensaje.',
      deepLink: '/chat/c-elena',
      priority: NotificationPriority.high,
    ),
    _Sample(
      channel: NotificationChannel.task,
      title: 'Nueva tarea publicada',
      body: 'Matemáticas Avanzadas — Práctica de Ecuaciones (entrega en 7 días).',
      deepLink: '/assignments/a-mat-002',
      priority: NotificationPriority.high,
    ),
    _Sample(
      channel: NotificationChannel.grade,
      title: 'Nota publicada',
      body: 'Historia Universal · Ensayo: 9.5 / 10',
      deepLink: '/grades',
      priority: NotificationPriority.normal,
    ),
    _Sample(
      channel: NotificationChannel.attendance,
      title: 'Ausencia registrada',
      body: 'Tu hijo Mateo fue marcado ausente en Física Cuántica.',
      deepLink: '/parent/dashboard',
      priority: NotificationPriority.high,
    ),
    _Sample(
      channel: NotificationChannel.announcement,
      title: 'Comunicado institucional',
      body: 'Reunión general de padres el jueves a las 6pm.',
      deepLink: '/alerts',
      priority: NotificationPriority.normal,
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<String?> deviceToken() async => 'demo-token-${_rand.nextInt(9999)}';

  @override
  Stream<AppNotification> get incoming => _incomingCtrl.stream;

  @override
  Stream<AppNotification> get onTap => _tapCtrl.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {}

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}

  @override
  Future<void> simulate(AppNotification n) async {
    _incomingCtrl.add(n);
  }

  /// Dispara una notificación aleatoria de las plantillas. Útil para el
  /// botón "Simular" de la pantalla de alertas.
  Future<AppNotification> triggerSample({NotificationChannel? channel}) async {
    final pool = channel == null
        ? _samples
        : _samples.where((s) => s.channel == channel).toList();
    final sample = pool[_rand.nextInt(pool.length)];
    final n = AppNotification(
      id: _uuid.v4(),
      channel: sample.channel,
      title: sample.title,
      body: sample.body,
      receivedAt: DateTime.now(),
      priority: sample.priority,
      read: false,
      deepLink: sample.deepLink,
      data: {'demo': true},
    );
    _incomingCtrl.add(n);
    return n;
  }

  /// Emula que el usuario tocó la notificación (para probar el deep-link
  /// sin salir de la app).
  void emulateTap(AppNotification n) => _tapCtrl.add(n);

  void dispose() {
    _incomingCtrl.close();
    _tapCtrl.close();
  }
}

class _Sample {
  const _Sample({
    required this.channel,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.priority,
  });
  final NotificationChannel channel;
  final String title;
  final String body;
  final String deepLink;
  final NotificationPriority priority;
}
