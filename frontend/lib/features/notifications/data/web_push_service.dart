import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../../../core/constants/env.dart';
import '../domain/entities.dart';
import '../domain/push_service.dart';
import 'demo_push_service.dart';

/// Push real vía **Web Push estándar (VAPID)** — Educa360 no usa Firebase.
///
/// Solo hay soporte de navegador para esto en **Flutter Web**; en Android/iOS
/// nativo no hay FCM/APNs configurado, así que fuera de web se delega todo a
/// [DemoPushService] (limitación documentada, no un fallo silencioso).
///
/// La entrega en segundo plano la maneja enteramente `web/push-sw.js` (el
/// Service Worker muestra la notificación del sistema con
/// `showNotification()`) — no depende de que la app Flutter esté abierta.
/// [incoming]/[onTap] de esta clase son solo para el flujo de demo
/// (`simulate`); no hay puente Service Worker → Dart implementado.
///
/// Requiere:
/// - `web/push-sw.js` (ya incluido).
/// - `--dart-define=VAPID_PUBLIC_KEY=...` (pública; la privada solo la usa
///   `backend/functions/send-push/`, nunca el cliente).
/// - Un usuario Supabase autenticado, para guardar la suscripción en
///   `devices.push_token`.
class WebPushService implements PushService {
  WebPushService({required this.client, required this.userId});

  final SupabaseClient client;
  final String? userId;

  final _fallback = DemoPushService();
  String? _endpoint;

  @override
  Future<void> init() async {
    if (!kIsWeb) return _fallback.init();
    if (Env.vapidPublicKey.isEmpty || userId == null) return;

    try {
      final registration =
          await web.window.navigator.serviceWorker.register('/push-sw.js'.toJS).toDart;

      final permission = (await web.Notification.requestPermission().toDart).toDart;
      if (permission != 'granted') return;

      var subscription = await registration.pushManager.getSubscription().toDart;
      subscription ??= await registration.pushManager
          .subscribe(
            web.PushSubscriptionOptionsInit(
              userVisibleOnly: true,
              applicationServerKey: _applicationServerKey(Env.vapidPublicKey),
            ),
          )
          .toDart;

      _endpoint = subscription.endpoint;
      await _saveSubscription(subscription);
    } catch (_) {
      // Navegador sin soporte de Push API, origen no seguro (http fuera de
      // localhost), o permiso denegado — no rompe la app, solo no hay push
      // real en esta sesión.
    }
  }

  JSAny _applicationServerKey(String vapidPublicKeyBase64Url) {
    final bytes = _urlBase64ToBytes(vapidPublicKeyBase64Url);
    return bytes.toJS;
  }

  Uint8List _urlBase64ToBytes(String base64Url) {
    final normalized = base64Url.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    return base64Decode(padded);
  }

  Future<void> _saveSubscription(web.PushSubscription subscription) async {
    final p256dhBuffer = subscription.getKey('p256dh');
    final authBuffer = subscription.getKey('auth');
    final payload = jsonEncode({
      'endpoint': subscription.endpoint,
      'keys': {
        'p256dh': p256dhBuffer == null ? null : base64UrlEncode(p256dhBuffer.toDart.asUint8List()),
        'auth': authBuffer == null ? null : base64UrlEncode(authBuffer.toDart.asUint8List()),
      },
    });

    final existing = await client
        .from('devices')
        .select('id')
        .eq('user_id', userId!)
        .eq('device_uuid', subscription.endpoint)
        .maybeSingle();
    if (existing == null) {
      await client.from('devices').insert({
        'user_id': int.parse(userId!),
        'device_uuid': subscription.endpoint,
        'platform': 'web',
        'push_token': payload,
        'active': true,
      });
    } else {
      await client
          .from('devices')
          .update({'push_token': payload, 'active': true})
          .eq('id', existing['id'] as Object);
    }
  }

  String base64UrlEncode(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  @override
  Future<String?> deviceToken() async => kIsWeb ? _endpoint : _fallback.deviceToken();

  @override
  Stream<AppNotification> get incoming => _fallback.incoming;

  @override
  Stream<AppNotification> get onTap => _fallback.onTap;

  @override
  Future<void> subscribeToTopic(String topic) async {
    // Web Push no tiene topics nativos (a diferencia de FCM); la
    // segmentación por institución/rol se resuelve en `send-push` filtrando
    // por `devices.user_id` / `users.institution_id`.
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}

  @override
  Future<void> simulate(AppNotification n) => _fallback.simulate(n);

  void dispose() => _fallback.dispose();
}
