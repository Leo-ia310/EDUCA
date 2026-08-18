import 'entities.dart';

/// Persistencia local del feed + contadores. Recibe notificaciones desde el
/// [PushService] y las guarda en Hive para que el usuario las revise en
/// `/alerts` aunque la app se cierre.
abstract class NotificationsRepository {
  Stream<List<AppNotification>> watchAll();
  Stream<int> watchUnread();

  Future<void> add(AppNotification notification);
  Future<void> markRead(String id);
  Future<void> markAllRead();
  Future<void> remove(String id);
  Future<void> clearAll();

  /// Semilla inicial cuando el feed está vacío (para demo). En producción
  /// no se usa.
  Future<void> seedIfEmpty(List<AppNotification> seeds);
}
