import 'dart:async';

import 'package:hive/hive.dart';

import '../domain/entities.dart';
import '../domain/notifications_repository.dart';
import 'models/local_notification.dart';

/// Repository que persiste el feed en Hive. Funciona tanto en modo demo
/// como con FCM real (siempre queremos un feed local para consultar sin
/// backend).
class HiveNotificationsRepository implements NotificationsRepository {
  HiveNotificationsRepository(this._box) {
    _emitAll();
    _emitUnread();
  }

  final Box<LocalNotification> _box;
  final _allCtrl = StreamController<List<AppNotification>>.broadcast();
  final _unreadCtrl = StreamController<int>.broadcast();

  List<AppNotification> _snapshot() {
    final list = _box.values.map((l) => l.toEntity()).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return list;
  }

  void _emitAll() => _allCtrl.add(_snapshot());
  void _emitUnread() {
    final n = _box.values.where((l) => !l.read).length;
    _unreadCtrl.add(n);
  }

  @override
  Stream<List<AppNotification>> watchAll() async* {
    yield _snapshot();
    yield* _allCtrl.stream;
  }

  @override
  Stream<int> watchUnread() async* {
    yield _box.values.where((l) => !l.read).length;
    yield* _unreadCtrl.stream;
  }

  @override
  Future<void> add(AppNotification n) async {
    await _box.put(n.id, LocalNotification.fromEntity(n));
    _emitAll();
    _emitUnread();
  }

  @override
  Future<void> markRead(String id) async {
    final entry = _box.get(id);
    if (entry == null || entry.read) return;
    entry.read = true;
    await _box.put(entry.id, entry);
    _emitAll();
    _emitUnread();
  }

  @override
  Future<void> markAllRead() async {
    for (final entry in _box.values) {
      if (!entry.read) {
        entry.read = true;
        await _box.put(entry.id, entry);
      }
    }
    _emitAll();
    _emitUnread();
  }

  @override
  Future<void> remove(String id) async {
    await _box.delete(id);
    _emitAll();
    _emitUnread();
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
    _emitAll();
    _emitUnread();
  }

  @override
  Future<void> seedIfEmpty(List<AppNotification> seeds) async {
    if (_box.isNotEmpty) return;
    for (final s in seeds) {
      await _box.put(s.id, LocalNotification.fromEntity(s));
    }
    _emitAll();
    _emitUnread();
  }
}
