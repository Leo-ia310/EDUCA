import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/services/local_notifications_service.dart';
import '../data/demo_push_service.dart';
import '../providers.dart';
import 'entities.dart';

const _uuid = Uuid();

/// Cablea todo el pipeline de notificaciones:
///
/// - `PushService.incoming` → persistir en el feed → mostrar heads-up local
///   si la app está en foreground (los mensajes background los renderiza
///   FCM directamente).
/// - `PushService.onTap` y `LocalNotificationsService.onTap` → deep-link a
///   la ruta de destino usando el `GoRouter` global.
///
/// Debe llamarse una vez, después de `runApp` (por ejemplo desde el
/// `initState` del root widget o desde el `Consumer` con `ref.listen`).
class NotificationsBootstrap {
  NotificationsBootstrap(this._ref) {
    _wire();
  }

  final Ref _ref;
  final _localNotifications = LocalNotificationsService.instance;
  final _subs = <StreamSubscription<dynamic>>[];

  bool _handled = false;

  Future<void> _wire() async {
    if (_handled) return;
    _handled = true;

    await _localNotifications.init();
    await _localNotifications.requestPermission();

    final push = _ref.read(pushServiceProvider);
    await push.init();

    // Nuevas notificaciones entrantes → feed + banner.
    _subs.add(push.incoming.listen(_onIncoming));

    // Tap desde FCM (background/terminated).
    _subs.add(push.onTap.listen(_onTap));

    // Tap desde notificación local (foreground).
    _subs.add(_localNotifications.onTap.listen(_onTap));

    // Semillas iniciales del feed para el modo demo.
    await _seedDemoIfEmpty();
  }

  Future<void> _onIncoming(AppNotification n) async {
    // Persistir en el feed.
    await _ref.read(notificationsRepositoryProvider).add(n);
    // Heads-up local (solo cuando estamos en foreground — FCM ya lo hace
    // en background/terminated).
    await _localNotifications.show(n);
  }

  Future<void> _onTap(AppNotification n) async {
    // Marcar leída y navegar al deep link.
    await _ref.read(notificationsRepositoryProvider).markRead(n.id);
    final link = n.deepLink;
    if (link == null || link.isEmpty) return;
    final router = _ref.read(goRouterProvider);
    router.push(link);
  }

  Future<void> _seedDemoIfEmpty() async {
    final now = DateTime.now();
    await _ref.read(notificationsRepositoryProvider).seedIfEmpty([
      AppNotification(
        id: _uuid.v4(),
        channel: NotificationChannel.message,
        title: 'Nuevo mensaje',
        body: 'Prof. Elena Ramírez te escribió: "Recuerda la práctica"',
        receivedAt: now.subtract(const Duration(minutes: 4)),
        priority: NotificationPriority.high,
        read: false,
        deepLink: '/chat/c-elena',
      ),
      AppNotification(
        id: _uuid.v4(),
        channel: NotificationChannel.grade,
        title: 'Nota publicada',
        body: 'Matemáticas · Cálculo Integral: 9.5',
        receivedAt: now.subtract(const Duration(hours: 3)),
        priority: NotificationPriority.normal,
        read: false,
        deepLink: '/grades',
      ),
      AppNotification(
        id: _uuid.v4(),
        channel: NotificationChannel.task,
        title: 'Recordatorio: tarea próxima',
        body: 'Ética · Ensayo vence mañana a las 23:59.',
        receivedAt: now.subtract(const Duration(hours: 6)),
        priority: NotificationPriority.high,
        read: false,
        deepLink: '/assignments/a-etica-001',
      ),
      AppNotification(
        id: _uuid.v4(),
        channel: NotificationChannel.announcement,
        title: 'Comunicado institucional',
        body: 'Reunión general de padres el jueves a las 6pm.',
        receivedAt: now.subtract(const Duration(days: 1)),
        priority: NotificationPriority.normal,
        read: true,
        deepLink: '/alerts',
      ),
    ]);
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}

/// Provider Riverpod que crea el bootstrap una vez. Se dispara desde el
/// `Educa360App` con un `ref.listen` que lo mantiene vivo.
final notificationsBootstrapProvider =
    Provider<NotificationsBootstrap>((ref) {
  final bootstrap = NotificationsBootstrap(ref);
  ref.onDispose(bootstrap.dispose);
  return bootstrap;
});

/// Handy: dispara la simulación (solo si el PushService actual es demo).
Future<void> simulateDemoNotification(WidgetRef ref,
    {NotificationChannel? channel}) async {
  final push = ref.read(pushServiceProvider);
  if (push is DemoPushService) {
    await push.triggerSample(channel: channel);
  }
}
