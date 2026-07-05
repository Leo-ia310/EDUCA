import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/env.dart';
import '../../core/services/hive_init.dart';
import 'data/demo_push_service.dart';
import 'data/firebase_push_service.dart';
import 'data/hive_notifications_repository.dart';
import 'domain/entities.dart';
import 'domain/notifications_repository.dart';
import 'domain/push_service.dart';

/// Bandera compartida por el bootstrap para elegir Demo o Firebase.
/// Si el binario no tiene `firebase_options.dart` configurado, dejar `true`
/// para no romper la app en modo mock.
const _forceDemoPush = true;

/// Servicio de push. En modo demo emite el flujo simulado; en producción
/// (cuando Firebase esté inicializado) usa FCM.
final pushServiceProvider = Provider<PushService>((ref) {
  if (_forceDemoPush || Env.isDemoMode) {
    return DemoPushService();
  }
  return FirebasePushService();
});

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  final box = ref.watch(notificationsBoxProvider);
  return HiveNotificationsRepository(box);
});

/// Feed vivo — usado por `/alerts` y por los badges.
final notificationsFeedProvider =
    StreamProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchAll();
});

final notificationsUnreadProvider = StreamProvider<int>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchUnread();
});
