// -----------------------------------------------------------------------------
// STUB (Firebase deshabilitado en el proyecto de demo).
//
// Este archivo mantiene la CLASE presente para no romper imports, pero NO
// depende de `firebase_messaging` — así el build de Android no requiere
// `google-services.json`.
//
// Para activar FCM real:
// 1) Descomentar firebase_core / firebase_messaging en pubspec.yaml.
// 2) `flutterfire configure` (genera firebase_options.dart).
// 3) Copiar google-services.json a android/app/.
// 4) En providers.dart poner `_forceDemoPush = false`.
// 5) Restaurar la implementación real (ver git history de este archivo).
// -----------------------------------------------------------------------------

import 'dart:async';

import '../domain/entities.dart';
import '../domain/push_service.dart';

class FirebasePushService implements PushService {
  FirebasePushService();

  final _incomingCtrl = StreamController<AppNotification>.broadcast();
  final _tapCtrl = StreamController<AppNotification>.broadcast();

  @override
  Future<void> init() async {
    throw StateError(
      'FirebasePushService está deshabilitado. Sigue los pasos del comentario '
      'para activarlo.',
    );
  }

  @override
  Future<String?> deviceToken() async => null;

  @override
  Stream<AppNotification> get incoming => _incomingCtrl.stream;

  @override
  Stream<AppNotification> get onTap => _tapCtrl.stream;

  @override
  Future<void> subscribeToTopic(String topic) async {}

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}

  void dispose() {
    _incomingCtrl.close();
    _tapCtrl.close();
  }
}
