import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/entities.dart';
import '../domain/notifications_repository.dart';

/// Feed real: lee las notificaciones del usuario autenticado desde el backend
/// (`/notifications`, filtradas por cuenta e institución) y las mantiene
/// frescas con un sondeo ligero. Nunca siembra datos de ejemplo.
class BackendNotificationsRepository implements NotificationsRepository {
  BackendNotificationsRepository(
    this._api, {
    Duration pollEvery = const Duration(seconds: 45),
  }) {
    _timer = Timer.periodic(pollEvery, (_) => refresh());
    refresh();
  }

  final BackendApiClient _api;
  Timer? _timer;
  final _ctrl = StreamController<List<AppNotification>>.broadcast();
  List<AppNotification> _items = const [];
  final DateTime _securityPromptAt = DateTime.now();
  bool _loaded = false;
  bool _securityPromptRead = false;
  bool _securityPromptHidden = false;

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }

  Future<void> refresh() async {
    try {
      final raw = await _api.get('/notifications');
      final list = raw is List ? raw : const [];
      _items = _withSecurityPrompt([
        for (final e in list)
          if (e is Map) _parse(Map<String, dynamic>.from(e)),
      ]);
    } catch (_) {
      // Sin red o sin sesión: mantenemos visible el aviso local de seguridad.
      _items = _withSecurityPrompt(_items);
    }
    _loaded = true;
    _emit();
  }

  List<AppNotification> _withSecurityPrompt(List<AppNotification> items) {
    final withoutPrompt = items
        .where((item) => item.id != 'security-2fa')
        .toList(growable: false);
    if (_securityPromptHidden) return withoutPrompt;
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
    return AppNotification(
      id: '${m['id']}',
      channel: NotificationChannel.fromCode(m['channel'] as String?),
      title: '${m['title'] ?? ''}',
      body: '${m['body'] ?? ''}',
      receivedAt:
          DateTime.tryParse('${m['receivedAt']}')?.toLocal() ?? DateTime.now(),
      priority: NotificationPriority.normal,
      read: m['read'] == true,
      data: data,
      deepLink: link is String && link.isNotEmpty ? link : null,
    );
  }

  void _emit() {
    if (!_ctrl.isClosed) _ctrl.add(List.unmodifiable(_items));
  }

  Stream<T> _watch<T>(T Function() read) async* {
    if (!_loaded) await refresh();
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
    _securityPromptHidden = true;
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
