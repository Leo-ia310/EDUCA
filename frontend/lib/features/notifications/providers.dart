import '../portal_access/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../../core/services/hive_init.dart';
import '../auth/presentation/auth_controller.dart';
import '../auth/presentation/query_auth_provider.dart';
import 'data/backend_notifications_repository.dart';
import 'data/demo_push_service.dart';
import 'data/hive_notifications_repository.dart';
import 'data/web_push_service_stub.dart'
    if (dart.library.html) 'data/web_push_service.dart';
import 'domain/entities.dart';
import 'domain/notifications_repository.dart';
import 'domain/push_service.dart';

/// Servicio de push. En modo demo (o sin cliente/sesión aún) emite el flujo
/// simulado; conectado usa Web Push estándar (VAPID) — Educa360 no usa
/// Firebase. Ver `data/web_push_service.dart` para el alcance (solo Flutter
/// Web; Android/iOS nativo queda en demo hasta que se sume un proveedor
/// compatible).
final pushServiceProvider = Provider<PushService>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (Env.isDemoMode || client == null || api == null || auth.user == null) {
    return DemoPushService();
  }
  return WebPushService(api: api, userId: auth.user!.id);
});

/// Demo: feed local (Hive) con semillas. Real: notificaciones del backend,
/// atadas al usuario (cambiar de cuenta recrea el repositorio y no mezcla
/// datos entre roles).
final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  ref.watch(portalFingerprintProvider);
  final api = ref.watch(backendApiClientProvider);
  final userId = ref.watch(queryAuthProvider).user?.id;
  if (!Env.isDemoMode && api != null && userId != null) {
    final repo = BackendNotificationsRepository(
      api,
      realtime: ref.watch(supabaseClientProvider),
      userId: userId,
    );
    ref.onDispose(repo.dispose);
    return repo;
  }
  final box = ref.watch(notificationsBoxProvider);
  return HiveNotificationsRepository(box);
});

/// Feed vivo — usado por `/alerts` y por los badges.
final notificationsFeedProvider = StreamProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchAll();
});

final notificationsUnreadProvider = StreamProvider<int>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchUnread();
});
