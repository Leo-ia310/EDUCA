import 'entities.dart';

/// Servicio de push notifications. Es agnóstico al proveedor (FCM en
/// producción, Demo en modo mock). El consumidor (repository) escucha el
/// stream [incoming] y persiste + muestra el banner.
abstract class PushService {
  /// Inicializa el servicio y solicita permisos.
  Future<void> init();

  /// Token del dispositivo — se envía al backend (`devices.push_token`).
  Future<String?> deviceToken();

  /// Stream de notificaciones entrantes. Incluye tanto los mensajes recibidos
  /// en foreground como los que abrieron la app desde background/terminated.
  Stream<AppNotification> get incoming;

  /// Se dispara cuando el usuario toca la notificación desde el system tray.
  Stream<AppNotification> get onTap;

  /// Suscribirse a un topic (ej. "institution_1" para difusión).
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);

  /// Herramienta de desarrollo: simula la llegada de una notificación (solo
  /// implementado por [DemoPushService]; los reales lo ignoran).
  Future<void> simulate(AppNotification n) async {}
}
