import 'dart:async';

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
  bool _loaded = false;

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }

  Future<void> refresh() async {
    try {
      final raw = await _api.get('/notifications');
      final list = raw is List ? raw : const [];
      _items = [
        for (final e in list)
          if (e is Map) _parse(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      // Sin red o sin sesión: se conserva lo último cargado (vacío al inicio).
    }
    _loaded = true;
    _emit();
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
