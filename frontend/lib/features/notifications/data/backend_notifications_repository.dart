import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/adaptive_refresh.dart';
import '../domain/entities.dart';
import '../domain/notifications_repository.dart';

/// Feed real: lee las notificaciones del usuario autenticado desde el backend
/// (`/notifications`, filtradas por cuenta e institución). Nunca siembra datos
/// de ejemplo.
///
/// Se mantiene al día de tres formas:
/// - **Tiempo real**: suscripción de Supabase Realtime a la tabla
///   `notifications` del usuario (llega al instante, p. ej. un mensaje de chat).
/// - **Al volver a la app** (resume) y al abrir la pantalla de alertas.
/// - Respaldo adaptativo con backoff si falla la red y conciliación espaciada
///   si Realtime funciona. Se suspende en segundo plano.
class BackendNotificationsRepository
    with WidgetsBindingObserver
    implements NotificationsRepository {
  BackendNotificationsRepository(
    this._api, {
    SupabaseClient? realtime,
    String? userId,
    Duration pollEvery = const Duration(seconds: 30),
  }) {
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _refreshDriver = AdaptiveRefresh(
        read: _refreshOnce, fallbackEvery: pollEvery, foreground: _foreground,);
    if (realtime != null && userId != null) _listenRealtime(realtime, userId);
    unawaited(refresh());
  }

  final BackendApiClient _api;
  late final AdaptiveRefresh _refreshDriver;
  bool _disposed = false;
  bool _foreground = true;
  SupabaseClient? _client;
  RealtimeChannel? _channel;
  final _ctrl = StreamController<List<AppNotification>>.broadcast();
  final _arrivals = StreamController<AppNotification>.broadcast();
  List<AppNotification> _items = const [];
  final _known = <String>{};
  final DateTime _securityPromptAt = DateTime.now();
  bool _loaded = false;
  bool _hasRemoteSnapshot = false;
  bool _securityPromptRead = false;
  bool _securityPromptHidden = false;
  bool _twoFactorEnabled = false;
  DateTime? _twoFactorCheckedAt;

  /// Notificaciones que llegan **después** de la primera carga (para mostrar
  /// un aviso local mientras la app está abierta).
  Stream<AppNotification> get arrivals => _arrivals.stream;

  void _listenRealtime(SupabaseClient client, String userId) {
    try {
      _client = client;
      _channel = client
          .channel('notifications:$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) => _refreshDriver.notifyEvent(),
          )
          .subscribe((status, error) => _refreshDriver.setRealtimeHealthy(
              status == RealtimeSubscribeStatus.subscribed,),);
    } catch (_) {
      // Sin realtime queda el sondeo y el refresco al volver a la app.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshDriver.dispose();
    final channel = _channel;
    if (channel != null) _client?.removeChannel(channel);
    _ctrl.close();
    _arrivals.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _twoFactorCheckedAt = null;
    _refreshDriver.setForeground(_foreground);
  }

  @override
  Future<void> refresh() async {
    await _refreshDriver.refresh();
  }

  Future<void> _refreshOnce() async {
    await _refreshTwoFactorStatus();
    if (_disposed || !_foreground) return;
    try {
      final raw = await _api.get('/notifications');
      if (_disposed || !_foreground) return;
      final list = raw is List ? raw : const [];
      final items = [
        for (final e in list)
          if (e is Map) _parse(Map<String, dynamic>.from(e)),
      ];
      if (_hasRemoteSnapshot) {
        for (final n in items) {
          if (!n.read && !_known.contains(n.id) && !_arrivals.isClosed) {
            _arrivals.add(n);
          }
        }
      }
      _known.addAll(items.map((n) => n.id));
      while (_known.length > 1000) {
        _known.remove(_known.first);
      }
      _hasRemoteSnapshot = true;
      _items = _withSecurityPrompt(items);
    } catch (_) {
      // Sin red o sin sesión: se conserva lo último cargado y el aviso local
      // de seguridad sigue visible.
      _items = _withSecurityPrompt(_items);
      _loaded = true;
      if (!_disposed && _foreground) _emit();
      rethrow;
    }
    _loaded = true;
    _emit();
  }

  /// Consulta el aviso de 2FA como máximo cada cinco minutos y al volver a
  /// primer plano. La pantalla de seguridad invalida el repositorio al cambiarlo.
  /// Si falla,
  /// se conserva el último valor conocido.
  Future<void> _refreshTwoFactorStatus() async {
    final at = _twoFactorCheckedAt;
    if (at != null && DateTime.now().difference(at).inMinutes < 5) return;
    _twoFactorCheckedAt = DateTime.now();
    try {
      final raw = await _api.get('/auth/2fa/status');
      if (_disposed || !_foreground) return;
      _twoFactorEnabled = raw is Map && raw['enabled'] == true;
    } catch (_) {}
  }

  /// Aviso local (no viene del backend) que invita a activar el 2FA; no se
  /// muestra si el usuario ya lo tiene activo.
  List<AppNotification> _withSecurityPrompt(List<AppNotification> items) {
    final withoutPrompt = items
        .where((item) => item.id != 'security-2fa')
        .toList(growable: false);
    if (_securityPromptHidden || _twoFactorEnabled) return withoutPrompt;
    return [_securityPrompt(), ...withoutPrompt];
  }

  AppNotification _securityPrompt() {
    return AppNotification(
      id: 'security-2fa',
      channel: NotificationChannel.system,
      title: 'Activa el 2FA',
      body: 'Agrega verificación en dos pasos para proteger tu cuenta escolar.',
      receivedAt: _securityPromptAt,
      priority: NotificationPriority.high,
      read: _securityPromptRead,
      deepLink: '/settings/security',
      iconOverride: Icons.verified_user_rounded,
    );
  }

  static AppNotification _parse(Map<String, dynamic> m) {
    final data = m['data'] is Map
        ? Map<String, dynamic>.from(m['data'] as Map)
        : <String, dynamic>{};
    final link = data['deepLink'] ?? data['deep_link'] ?? data['route'];
    final channel = NotificationChannel.fromCode(m['channel'] as String?);
    return AppNotification(
      id: '${m['id']}',
      channel: channel,
      title: '${m['title'] ?? ''}',
      body: '${m['body'] ?? ''}',
      receivedAt:
          DateTime.tryParse('${m['receivedAt']}')?.toLocal() ?? DateTime.now(),
      priority: channel == NotificationChannel.message
          ? NotificationPriority.high
          : NotificationPriority.normal,
      read: m['read'] == true,
      data: data,
      deepLink: link is String && link.isNotEmpty ? link : null,
    );
  }

  void _emit() {
    if (!_disposed && _foreground && !_ctrl.isClosed) {
      _ctrl.add(List.unmodifiable(_items));
    }
  }

  Stream<T> _watch<T>(T Function() read) async* {
    if (!_loaded) await refresh();
    if (_disposed) return;
    yield read();
    yield* _ctrl.stream.map((_) => read());
  }

  @override
  Stream<List<AppNotification>> watchAll() => _watch(() => _items);

  @override
  Stream<int> watchUnread() =>
      _watch(() => _items.where((n) => !n.read).length);

  /// Las notificaciones reales las crea el backend; aquí solo se refresca.
  @override
  Future<void> add(AppNotification notification) => refresh();

  @override
  Future<void> markRead(String id) async {
    if (id == 'security-2fa') {
      _securityPromptRead = true;
      _items = _withSecurityPrompt(_items);
      _emit();
      return;
    }
    _items = [for (final n in _items) n.id == id ? n.copyWith(read: true) : n];
    _emit();
    try {
      await _api.patch('/notifications/$id/read');
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> markAllRead() async {
    _securityPromptRead = true;
    _items = [for (final n in _items) n.copyWith(read: true)];
    _emit();
    try {
      await _api.post('/notifications/read-all');
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> remove(String id) async {
    if (id == 'security-2fa') {
      _securityPromptHidden = true;
      _items = _withSecurityPrompt(_items);
      _emit();
      return;
    }
    _items = _items.where((n) => n.id != id).toList();
    _emit();
    try {
      await _api.delete('/notifications/$id');
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> clearAll() async {
    _items = const [];
    _emit();
    try {
      await _api.delete('/notifications');
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> seedIfEmpty(List<AppNotification> seeds) async {}
}
